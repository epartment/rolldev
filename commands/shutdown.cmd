#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if (( ${#ROLL_PARAMS[@]} > 0 )); then
    fatal "Unsupported argument ${ROLL_PARAMS[0]}"
fi

assertDockerRunning

## allow return codes from sub-process to bubble up normally
trap '' ERR

## Every compose project with a running container, as "<project>\t<working dir>". Compose stamps
## both labels on each container it creates, and env.cmd passes the project directory explicitly,
## so the working dir is the directory `roll env down` has to run in.
function listRunningComposeProjects() {
    docker container ls \
        --filter "label=com.docker.compose.project" \
        --format '{{.Label "com.docker.compose.project"}}{{"\t"}}{{.Label "com.docker.compose.project.working_dir"}}' \
        | sort -u

    return 0
}

## The names of every environment roll created a network for, one per line. networks.base.yml labels
## each environment network with its name, which is how a roll environment is recognised after its
## project directory or .env.roll has gone.
function listRollNetworkEnvNames() {
    docker network ls \
        --filter "label=dev.roll.environment.name" \
        --format '{{.Label "dev.roll.environment.name"}}'

    return 0
}

## The environment name a project's .env.roll declares, or nothing
function envNameInDir() {
    local dir="$1"

    grep -m1 '^ROLL_ENV_NAME=' "${dir}/.env.roll" 2>/dev/null | cut -d '=' -f2- | tr -d '\r"'\'

    return 0
}

envNames=()
envDirs=()
skipped=0
rollNetworkEnvNames="$(listRollNetworkEnvNames)"

while IFS=$'\t' read -r project dir; do
    [[ -z "${project}" || "${project}" == "roll" ]] && continue

    if [[ -z "${dir}" || ! -f "${dir}/.env.roll" ]]; then
        ## not a roll environment: a compose project roll did not start
        [[ $'\n'"${rollNetworkEnvNames}"$'\n' == *$'\n'"${project}"$'\n'* ]] || continue

        warning "Skipping ${project}: ${dir:-its project directory}/.env.roll no longer exists, so roll env down cannot be run for it. Stop it with: docker stop \$(docker ps -q --filter label=com.docker.compose.project=${project})"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$(envNameInDir "${dir}")" != "${project}" ]]; then
        warning "Skipping ${project}: ${dir}/.env.roll no longer names it, so roll env down there would target another environment. Stop it with: docker stop \$(docker ps -q --filter label=com.docker.compose.project=${project})"
        skipped=$((skipped + 1))
        continue
    fi

    envNames+=("${project}")
    envDirs+=("${dir}")
done < <(listRunningComposeProjects)

if (( ${#envNames[@]} == 0 && skipped == 0 )); then
    info "No running environments found."
fi

failed=()
i=0
while (( i < ${#envNames[@]} )); do
    info "Shutting down ${envNames[$i]} (${envDirs[$i]})"
    if ! (cd "${envDirs[$i]}" && "${ROLL_DIR}/bin/roll" env down); then
        error "roll env down failed for ${envNames[$i]}"
        failed+=("${envNames[$i]}")
    fi
    i=$((i + 1))
done

coreServicesDown=0
if [[ -n "$(docker container ls -aq --filter "label=com.docker.compose.project=roll")" ]]; then
    info "Shutting down the RollDev core services"
    if "${ROLL_DIR}/bin/roll" svc down; then
        coreServicesDown=1
    else
        error "roll svc down failed"
        failed+=("core services")
    fi
else
    info "RollDev core services are not running."
fi

if (( ${#failed[@]} > 0 )); then
    fatal "Shutdown incomplete, failed: ${failed[*]}"
fi

if (( skipped > 0 )); then
    fatal "Shut down ${#envNames[@]} environment(s); ${skipped} left running, see above."
fi

if [[ ${coreServicesDown} -eq 1 ]]; then
    success "Shut down ${#envNames[@]} environment(s) and the RollDev core services."
else
    success "Shut down ${#envNames[@]} environment(s)."
fi
