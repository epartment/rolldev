#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-processes (docker cp, etc.) to bubble up normally
trap '' ERR

## The --all check comes before the help/ROLL_PARAMS check below, mirroring
## copyfromcontainer.cmd's ordering (RECLU H1: copytocontainer previously tested ROLL_PARAMS
## first, which is always empty here since this command is on ROLL_CMD_ANYARGS - --all could
## never be reached).
case "$1" in
  -h|--help)
    ## Do NOT re-invoke `roll copytocontainer --help` here - see copyfromcontainer.cmd for why.
    source "${ROLL_DIR}/commands/usage.cmd"
    ;;
  --all)
    docker cp "${ROLL_ENV_PATH}/./" "$(roll env ps -q php-fpm)":/var/www/html/
    success "Completed copying all files from host to container."
    "${ROLL_DIR}/bin/roll" fixowns
    "${ROLL_DIR}/bin/roll" fixperms
    ;;
  *)
    if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
      source "${ROLL_DIR}/commands/usage.cmd"
    fi
    FILE_OR_FOLDER="${ROLL_PARAMS[0]}"
    ## dirname belongs on the DESTINATION, not on the source: `docker cp <src> <dst>/` places <src>
    ## inside <dst>, so naming the source's parent as the source copied the entire project root
    ## into /var/www/html/<folder>. One expression covers both a file and a directory. The
    ## destination parent has to exist inside the container - docker cp does not create it - which
    ## it need not for a path the container has never seen.
    CONTAINER_ID="$(roll env ps -q php-fpm)"
    DEST_PARENT="/var/www/html/$(dirname -- "${FILE_OR_FOLDER}")"
    docker exec "${CONTAINER_ID}" mkdir -p -- "${DEST_PARENT}"
    docker cp "${ROLL_ENV_PATH}/${FILE_OR_FOLDER}" "${CONTAINER_ID}":"${DEST_PARENT}"/
    success "Completed copying ${FILE_OR_FOLDER} from host to container."
    "${ROLL_DIR}/bin/roll" fixowns "${FILE_OR_FOLDER}"
    "${ROLL_DIR}/bin/roll" fixperms "${FILE_OR_FOLDER}"
    ;;
esac
