#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## `status` is on roll's ROLL_CMD_ANYARGS list (needed so --format reaches this script), so roll's
## own parser stops at the first dash-prefixed argument and passes it straight through here with
## ROLL_PARAMS empty. Parse flags from "$@", not ROLL_PARAMS.
STATUS_FORMAT="human"
while (( "$#" )); do
    case "$1" in
        -h|--help)
            ## Do NOT re-invoke `roll status --help` here - status is on ROLL_CMD_ANYARGS, so
            ## re-invoking roll lands right back on this branch and forks until killed.
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            STATUS_FORMAT="${1#*=}"
            shift
            ;;
        --format)
            ## `shift 2` would abort the whole CLI under bin/roll's `set -e` if --format is the
            ## last argument ($# == 1): shift returns non-zero when the count exceeds $#.
            STATUS_FORMAT="${2:-}"
            shift
            (( $# )) && shift
            ;;
        *)
            fatal "Unsupported argument $1"
            ;;
    esac
done

if [[ "${STATUS_FORMAT}" != "human" && "${STATUS_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${STATUS_FORMAT}' (expected: human, json)"
fi

assertDockerRunning

## The roll core network is always named "roll" (docker/docker-compose.yml networks.default.name);
## reading it from a fixed constant instead of scraping the compose YAML.
rollNetworkName="roll"
rollNetworkId=$(docker network ls -q --filter name="${rollNetworkName}")

OLDIFS="$IFS"
IFS=$'\n'
if command -v mapfile >/dev/null 2>&1; then
    mapfile -t projectNetworkList < <(docker network ls --format '{{.Name}}' -q --filter "label=dev.roll.environment.name")
else
    projectNetworkList=()
    while IFS= read -r net; do
        projectNetworkList+=("$net")
    done < <(docker network ls --format '{{.Name}}' -q --filter "label=dev.roll.environment.name")
fi
IFS="$OLDIFS"

## Raw per-project fields, parallel arrays, collected alongside messageList so json rendering
## below needs no extra docker calls.
jsonProjectNames=()
jsonProjectTypes=()
jsonProjectDirs=()
jsonProjectUrls=()
jsonProjectNetworks=()
jsonProjectContainerCounts=()

messageList=()
if (( ${#projectNetworkList[@]} > 0 )); then
    lastIdx=$(( ${#projectNetworkList[@]} - 1 ))
    lastNetwork="${projectNetworkList[$lastIdx]}"
else
    lastNetwork=""
fi
for projectNetwork in "${projectNetworkList[@]}"; do
    [[ -z "${projectNetwork}" || "${projectNetwork}" == "${rollNetworkName}" ]] && continue # Skip empty project network names (if any)

    prefix="${projectNetwork%_default}"
    prefixLen="${#prefix}"
    ((prefixLen+=1))
    projectContainers=$(docker network inspect --format '{{ range $k,$v := .Containers }}{{ $nameLen := len $v.Name }}{{ if gt $nameLen '"${prefixLen}"' }}{{ $prefix := slice $v.Name 0 '"${prefixLen}"' }}{{ if eq $prefix "'"${prefix}-"'" }}{{ println $v.Name }}{{end}}{{end}}{{end}}' "${projectNetwork}")
    container=$(echo "$projectContainers" | head -n1)

    [[ -z "${container}" ]] && continue # Project is not running, skip it

    projectDir=$(docker container inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container")
    projectName=$(grep -m1 '^ROLL_ENV_NAME=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    projectType=$(grep -m1 '^ROLL_ENV_TYPE=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    traefikDomain=$(grep -m1 '^TRAEFIK_DOMAIN=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    traefikSubDomain=$(grep -m1 '^TRAEFIK_SUBDOMAIN=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    containerCount=$(echo "$projectContainers" | wc -l | tr -d ' ')
    projectUrl="https://${traefikSubDomain}.${traefikDomain}"

    jsonProjectNames+=("${projectName}")
    jsonProjectTypes+=("${projectType}")
    jsonProjectDirs+=("${projectDir}")
    jsonProjectUrls+=("${projectUrl}")
    jsonProjectNetworks+=("${projectNetwork}")
    jsonProjectContainerCounts+=("${containerCount}")

    messageList+=("    \033[1;35m${projectName}\033[0m a \033[36m${projectType}\033[0m project")
    messageList+=("       Project Directory: \033[33m${projectDir}\033[0m")
    messageList+=("       Project URL: \033[94m${projectUrl}\033[0m")
    messageList+=("       Docker Network: \033[33m${projectNetwork}\033[0m")
    messageList+=("       Containers Running: \033[33m${containerCount}\033[0m")

    [[ "$projectNetwork" != "$lastNetwork" ]] && messageList+=("")
done

## Enabled core services (name, running/stopped) collected alongside the human table below.
jsonServiceNames=()
jsonServiceStates=()

if [[ "${STATUS_FORMAT}" != "json" ]]; then
    if (( ${#messageList[@]} > 0 )); then
        if [[ -z "${rollNetworkId}" ]]; then
            echo -e "Found the following \033[32mrunning\033[0m projects; however, \033[31mRollDev core services are currently not running\033[0m:"
        else
            echo -e "Found the following \033[32mrunning\033[0m environments:"
        fi
        for line in "${messageList[@]}"; do
            echo -e "$line"
        done
    else
        echo "No running environments found."
    fi
fi

if [[ -n "${rollNetworkId}" ]]; then
    if [[ "${STATUS_FORMAT}" != "json" ]]; then
        echo
        echo -e "RollDev Services (enabled -> running):"
    fi

    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        initConfigSchema
        loadConfigFromFile "${ROLL_HOME_DIR}/.env"
    fi
    # Read through the schema so the default (1) is authoritative, matching svc.cmd
    portainerEnabled="$(getConfig ROLL_SERVICE_PORTAINER 1)"
    startpageEnabled="$(getConfig ROLL_SERVICE_STARTPAGE 1)"

    services=(traefik dnsmasq mailhog tunnel)
    [[ "${portainerEnabled}" == 1 ]] && services+=(portainer)
    [[ "${startpageEnabled}" == 1 ]] && services+=(startpage)

    [[ "${STATUS_FORMAT}" != "json" ]] && printf '  %-12s %-10s %-20s %s\n' "NAME" "STATE" "STATUS" "PORTS"
    for svc in "${services[@]}"; do
        name=$(docker ps --filter "name=^${svc}$" --format '{{.Names}}')
        state=$(docker ps --filter "name=^${svc}$" --format '{{.State}}')
        status=$(docker ps --filter "name=^${svc}$" --format '{{.Status}}')
        ports=$(docker ps --filter "name=^${svc}$" --format '{{.Ports}}')

        jsonServiceNames+=("${svc}")
        if [[ -z "${name}" ]]; then
            jsonServiceStates+=("stopped")
            [[ "${STATUS_FORMAT}" != "json" ]] && printf '  %-12s %-10s %-20s -\n' "${svc}" "stopped" "Exited"
        else
            [[ "${state}" == "running" ]] && jsonServiceStates+=("running") || jsonServiceStates+=("stopped")
            [[ "${STATUS_FORMAT}" != "json" ]] && printf '  %-12s %-10s %-20s %s\n' "${name}" "${state}" "${status}" "${ports}"
        fi
    done
fi

if [[ "${STATUS_FORMAT}" == "json" ]]; then
    out="{\"projects\":["
    i=0
    while [[ $i -lt ${#jsonProjectNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{"
        out+="\"name\":\"$(jsonEscape "${jsonProjectNames[$i]}")\","
        out+="\"type\":\"$(jsonEscape "${jsonProjectTypes[$i]}")\","
        out+="\"dir\":\"$(jsonEscape "${jsonProjectDirs[$i]}")\","
        out+="\"url\":\"$(jsonEscape "${jsonProjectUrls[$i]}")\","
        out+="\"network\":\"$(jsonEscape "${jsonProjectNetworks[$i]}")\","
        out+="\"containers\":${jsonProjectContainerCounts[$i]}"
        out+="}"
        i=$((i + 1))
    done
    out+="],\"services\":["
    i=0
    while [[ $i -lt ${#jsonServiceNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{\"name\":\"$(jsonEscape "${jsonServiceNames[$i]}")\",\"status\":\"${jsonServiceStates[$i]}\"}"
        i=$((i + 1))
    done
    out+="]}"
    printf '%s\n' "${out}"
fi
