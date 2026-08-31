#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## `doctor` is on roll's ROLL_CMD_ANYARGS list (needed so --format reaches this script - also true
## when reached via `roll env doctor`, since `env` is already anyargs), so roll's own parser stops
## at the first dash-prefixed argument and leaves it in "$@". Parse flags from "$@", not
## ROLL_PARAMS.
DOCTOR_FORMAT="human"
doctorArgs=("$@")
i=0
while [[ $i -lt ${#doctorArgs[@]} ]]; do
    case "${doctorArgs[$i]}" in
        -h|--help)
            ## Do NOT re-invoke `roll doctor --help` here - doctor is on ROLL_CMD_ANYARGS, so
            ## re-invoking roll lands right back on this branch and forks until killed.
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            DOCTOR_FORMAT="${doctorArgs[$i]#*=}"
            ;;
        --format)
            i=$((i + 1))
            DOCTOR_FORMAT="${doctorArgs[$i]:-}"
            ;;
        *)
            fatal "Unsupported argument ${doctorArgs[$i]}"
            ;;
    esac
    i=$((i + 1))
done

if [[ "${DOCTOR_FORMAT}" != "human" && "${DOCTOR_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${DOCTOR_FORMAT}' (expected: human, json)"
fi

## Per-check results, in the order the checks run. Rendered as a table/box for human output or a
## {check, ok, detail} array for --format json.
CHECK_NAMES=()
CHECK_OK=()
CHECK_DETAILS=()

## recordCheck <name> <0|1> <detail>
function recordCheck() {
    CHECK_NAMES+=("$1")
    CHECK_OK+=("$2")
    CHECK_DETAILS+=("$3")
    return 0
}

## Renders every recorded check and sets DOCTOR_ANY_FAILED (0/1) as a global rather than relying on
## a function return status - bin/roll sources this file under `set -e`, and a plain function call
## returning non-zero at the top level would kill the whole command before the caller could act on
## the result.
DOCTOR_ANY_FAILED=0
function renderDoctorReport() {
    DOCTOR_ANY_FAILED=0
    local idx=0
    while [[ $idx -lt ${#CHECK_OK[@]} ]]; do
        [[ "${CHECK_OK[$idx]}" == "0" ]] && DOCTOR_ANY_FAILED=1
        idx=$((idx + 1))
    done

    if [[ "${DOCTOR_FORMAT}" == "json" ]]; then
        local out="{\"checks\":["
        idx=0
        while [[ $idx -lt ${#CHECK_NAMES[@]} ]]; do
            [[ $idx -gt 0 ]] && out+=","
            local okWord="false"
            [[ "${CHECK_OK[$idx]}" == "1" ]] && okWord="true"
            out+="{\"check\":\"$(jsonEscape "${CHECK_NAMES[$idx]}")\","
            out+="\"ok\":${okWord},"
            out+="\"detail\":\"$(jsonEscape "${CHECK_DETAILS[$idx]}")\"}"
            idx=$((idx + 1))
        done
        out+="],\"ok\":$([[ ${DOCTOR_ANY_FAILED} -eq 0 ]] && echo true || echo false)}"
        printf '%s\n' "${out}"
    else
        ## Plain text, deliberately with no ANSI in the lines themselves - styledBox's non-TTY
        ## fallback (utils/core.sh box()) measures column width from raw character count, so an
        ## embedded escape sequence would misalign the border.
        local lines=()
        idx=0
        while [[ $idx -lt ${#CHECK_NAMES[@]} ]]; do
            local mark="FAIL"
            [[ "${CHECK_OK[$idx]}" == "1" ]] && mark="OK  "
            lines+=("$(printf '%s  %-24s %s' "${mark}" "${CHECK_NAMES[$idx]}" "${CHECK_DETAILS[$idx]}")")
            idx=$((idx + 1))
        done

        if [[ ${DOCTOR_ANY_FAILED} -eq 0 ]]; then
            styledBox 2 "roll env doctor: ${ROLL_ENV_NAME:-environment}" "" "${lines[@]}" "" "All checks passed."
        else
            styledBox 1 "roll env doctor: ${ROLL_ENV_NAME:-environment}" "" "${lines[@]}" "" "One or more checks failed."
        fi
    fi

    return 0
}

## Loads .env.roll without the usual `|| exit $?` pattern most project-scoped commands use - a
## doctor tool that dies on a bare stderr line instead of naming the failure in its own report
## defeats the point of having a report.
doctorEnvPathStatus=0
ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)" || doctorEnvPathStatus=$?

if [[ ${doctorEnvPathStatus} -ne 0 || -z "${ROLL_ENV_PATH}" ]]; then
    recordCheck "env-config" 0 "No .env.roll found in this directory or its parents. Run 'roll env-init' first."
    renderDoctorReport
    exit "${DOCTOR_ANY_FAILED}"
fi

doctorLoadConfigStatus=0
loadEnvConfig "${ROLL_ENV_PATH}" || doctorLoadConfigStatus=$?

if [[ ${doctorLoadConfigStatus} -ne 0 ]]; then
    recordCheck "env-config" 0 "Failed to load ${ROLL_ENV_PATH}/.env.roll."
    renderDoctorReport
    exit "${DOCTOR_ANY_FAILED}"
fi

recordCheck "env-config" 1 "Environment '${ROLL_ENV_NAME}' (${ROLL_ENV_TYPE}) loaded from ${ROLL_ENV_PATH}/.env.roll."

if docker system info >/dev/null 2>&1; then
    recordCheck "docker" 1 "Docker daemon is reachable."
else
    recordCheck "docker" 0 "Docker daemon is not reachable. Start Docker and try again."
fi

## Containers healthy - reuses the healthchecks added to environments/includes/*.base.yml rather
## than re-implementing probes. One docker ps call for every container this project has (mirrors
## the single-call pattern in describe.cmd - a per-service lookup measured 9.8s against 1.3s and
## was reverted there), then one batched docker inspect for health status instead of one call per
## container.
function checkContainerHealth() {
    local containerIds=() containerNames=() containerServices=() containerStates=()
    local line cId cName cService cState
    while IFS='|' read -r cId cName cService cState; do
        [[ -z "${cId}" ]] && continue
        containerIds+=("${cId}")
        containerNames+=("${cName}")
        containerServices+=("${cService}")
        containerStates+=("${cState}")
    done < <(docker ps -a \
        --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
        --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.service"}}|{{.State}}' 2>/dev/null)

    if [[ ${#containerIds[@]} -eq 0 ]]; then
        recordCheck "containers" 0 "No containers found for '${ROLL_ENV_NAME}'. Is the environment running ('roll env up')?"
        return 0
    fi

    ## Parsed into parallel arrays with pure bash string handling (no per-container grep/cut fork)
    ## rather than re-filtering the raw docker inspect output inside the lookup loop below.
    local healthNames=() healthStatuses=()
    local healthLine healthName healthStatus
    while IFS='~' read -r healthName healthStatus; do
        [[ -z "${healthName}" ]] && continue
        healthNames+=("${healthName#/}")
        healthStatuses+=("${healthStatus}")
    done < <(docker inspect \
        --format '{{.Name}}~{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "${containerIds[@]}" 2>/dev/null)

    local idx=0 health=""
    while [[ $idx -lt ${#containerIds[@]} ]]; do
        health=""
        local hIdx=0
        while [[ $hIdx -lt ${#healthNames[@]} ]]; do
            if [[ "${healthNames[$hIdx]}" == "${containerNames[$idx]}" ]]; then
                health="${healthStatuses[$hIdx]}"
                break
            fi
            hIdx=$((hIdx + 1))
        done

        if [[ "${containerStates[$idx]}" != "running" ]]; then
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is ${containerStates[$idx]}, not running."
        elif [[ "${health}" == "healthy" ]]; then
            recordCheck "container:${containerServices[$idx]}" 1 "${containerNames[$idx]} is running and healthy."
        elif [[ "${health}" == "none" || -z "${health}" ]]; then
            recordCheck "container:${containerServices[$idx]}" 1 "${containerNames[$idx]} is running (no healthcheck configured)."
        elif [[ "${health}" == "starting" ]]; then
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is running but its healthcheck is still starting."
        else
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is running but reports health '${health}'."
        fi
        idx=$((idx + 1))
    done
    return 0
}
checkContainerHealth

## Required host ports free. Per-project containers never publish ports directly (they route
## through the shared traefik container on the roll network - see describe.cmd's PROJECT_URL and
## environments/includes/*.base.yml's traefik labels), so what every project actually depends on
## is the fixed set of ports the global roll stack publishes (docker/docker-compose.yml): traefik
## on 80/443 and dnsmasq on 53/udp. If the owning container is running, docker already proved the
## port is bound correctly (it refuses to start otherwise); only when it is not running do we probe
## the port directly to tell "free" (not started yet) apart from "occupied by something else".
function checkGlobalPort() {
    local port="$1" proto="$2" containerName="$3" label="$4"
    local state=""
    state="$(docker ps --filter "name=^${containerName}$" --format '{{.State}}' 2>/dev/null)" || true

    if [[ "${state}" == "running" ]]; then
        recordCheck "port-${port}" 1 "${label} (${port}/${proto}) is bound by the running ${containerName} container."
        return 0
    fi

    local occupied=0
    if command -v lsof >/dev/null 2>&1; then
        if [[ "${proto}" == "udp" ]]; then
            lsof -nP -iUDP:"${port}" >/dev/null 2>&1 && occupied=1 || true
        else
            lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && occupied=1 || true
        fi
    fi

    if [[ ${occupied} -eq 1 ]]; then
        recordCheck "port-${port}" 0 "${label} (${port}/${proto}) is occupied by another process and ${containerName} is not running."
    else
        recordCheck "port-${port}" 1 "${label} (${port}/${proto}) is free (${containerName} is not currently running)."
    fi
    return 0
}
checkGlobalPort 80 tcp traefik "Traefik HTTP"
checkGlobalPort 443 tcp traefik "Traefik HTTPS"
checkGlobalPort 53 udp dnsmasq "dnsmasq DNS"

if [[ "${ROLL_BROWSERSYNC:-0}" == "1" && "${ROLL_PUBLISH_PORTS:-1}" == "1" ]]; then
    browsersyncContainer="${ROLL_ENV_NAME}-browsersync-1"
    browsersyncState=""
    browsersyncState="$(docker ps --filter "name=^${browsersyncContainer}$" --format '{{.State}}' 2>/dev/null)" || true
    if [[ "${browsersyncState}" == "running" ]]; then
        recordCheck "port-browsersync" 1 "BrowserSync ports are bound by the running ${browsersyncContainer} container."
    else
        recordCheck "port-browsersync" 1 "BrowserSync is enabled but ${browsersyncContainer} is not running yet; ports are assigned at 'roll env up'."
    fi
fi

## Configured search engine answers /_cluster/health non-red and accepts a throwaway index write.
## A green cluster that cannot be written to (e.g. a disk watermark hit, read-only-allow-delete) is
## exactly the failure a health-only probe would miss. Reached through traefik on the project
## domain, not the container's internal port - matches how every other service in this project is
## already reachable from the host (see describe.cmd's PROJECT_URL / opensearch.base.yml's traefik
## labels), so this needs no `roll env exec`.
function checkSearchEngine() {
    local engine="$1"
    local engineLabel=""
    engineLabel="$(capitalize "${engine}")"
    local baseUrl="https://${engine}.${TRAEFIK_DOMAIN}"

    local health="" status=""
    health="$(curl -sk -m 5 "${baseUrl}/_cluster/health" 2>/dev/null)" || true
    status="$(printf '%s' "${health}" | grep -o '"status":"[a-z]*"' | cut -d'"' -f4)"

    if [[ -z "${status}" ]]; then
        recordCheck "search-engine:${engine}" 0 "${engineLabel} did not answer at ${baseUrl}/_cluster/health."
        return 0
    fi

    if [[ "${status}" == "red" ]]; then
        recordCheck "search-engine:${engine}" 0 "${engineLabel} cluster health is red at ${baseUrl}."
        return 0
    fi

    recordCheck "search-engine:${engine}" 1 "${engineLabel} cluster health is ${status} at ${baseUrl}."

    local probeIndex="roll-doctor-probe"
    local writeCode=""
    writeCode="$(curl -sk -m 5 -o /dev/null -w '%{http_code}' -X PUT "${baseUrl}/${probeIndex}" \
        -H 'Content-Type: application/json' -d '{}' 2>/dev/null)" || true
    curl -sk -m 5 -o /dev/null -X DELETE "${baseUrl}/${probeIndex}" 2>/dev/null || true

    if [[ "${writeCode}" == "200" || "${writeCode}" == "201" ]]; then
        recordCheck "search-engine-write:${engine}" 1 "${engineLabel} accepted a throwaway index write at ${baseUrl}/${probeIndex}."
    else
        recordCheck "search-engine-write:${engine}" 0 "${engineLabel} rejected a throwaway index write at ${baseUrl}/${probeIndex} (HTTP ${writeCode:-no response})."
    fi
    return 0
}

if [[ "${ROLL_OPENSEARCH:-0}" == "1" ]]; then
    checkSearchEngine "opensearch"
fi
if [[ "${ROLL_ELASTICSEARCH:-0}" == "1" ]]; then
    checkSearchEngine "elasticsearch"
fi
if [[ "${ROLL_OPENSEARCH:-0}" != "1" && "${ROLL_ELASTICSEARCH:-0}" != "1" ]]; then
    recordCheck "search-engine" 1 "No search engine enabled for this environment."
fi

## Disk headroom on the Docker data root. DockerRootDir lives inside a VM on Docker Desktop /
## OrbStack, so it is not reachable from the host filesystem there; probe from inside an
## already-running project container instead, which sees the real backing storage regardless of
## host OS. Only falls back to spinning up a new container when nothing from this project is
## running to probe from.
function checkDiskHeadroom() {
    local dockerRoot="" dfLine=""
    dockerRoot="$(docker system info --format '{{.DockerRootDir}}' 2>/dev/null)" || true

    if [[ -n "${dockerRoot}" && -d "${dockerRoot}" ]]; then
        dfLine="$(df -Pk "${dockerRoot}" 2>/dev/null | tail -n1)"
    fi

    if [[ -z "${dfLine}" ]]; then
        local probeContainer=""
        probeContainer="$(docker ps \
            --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
            --filter "status=running" \
            --format '{{.Names}}' 2>/dev/null | head -n1)"
        if [[ -n "${probeContainer}" ]]; then
            dfLine="$(docker exec "${probeContainer}" df -Pk / 2>/dev/null | tail -n1)"
        fi
    fi

    if [[ -z "${dfLine}" ]]; then
        recordCheck "disk" 0 "Could not determine Docker data root disk usage (no running container to probe and the Docker data root is not reachable from the host)."
        return 0
    fi

    local availKb="" usePercent="" availGb="" minGb=5
    availKb="$(echo "${dfLine}" | awk '{print $4}')"
    usePercent="$(echo "${dfLine}" | awk '{print $5}')"
    availGb=$(( ${availKb:-0} / 1024 / 1024 ))

    if [[ ${availGb} -lt ${minGb} ]]; then
        recordCheck "disk" 0 "Only ${availGb}GB free on the Docker data root (${usePercent} used) - below the ${minGb}GB minimum."
    else
        recordCheck "disk" 1 "${availGb}GB free on the Docker data root (${usePercent} used)."
    fi
    return 0
}
checkDiskHeadroom

renderDoctorReport
exit "${DOCTOR_ANY_FAILED}"
