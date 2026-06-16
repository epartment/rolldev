#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
    warning "This command is only available for Magento 2 projects" && exit 1
fi

if [[ ${ROLL_DB:-1} -eq 0 ]]; then
    fatal "Database environment is not used (ROLL_DB=0)."
fi

## load connection information from the running db container
DB_CONTAINER=$(roll env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service. Is the environment running?"
fi

eval "$(
    docker container inspect "${DB_CONTAINER}" --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQL_"
)"

## allow return codes from sub-process to bubble up normally
trap '' ERR

## default input directory (project-relative, produced by `roll mydumper`)
MYLOADER_INPUT_DIR="var/mydumper"

## inject connection defaults unless the caller already supplied them
HAS_DIRECTORY=0
HAS_DATABASE=0
HAS_OVERWRITE=0
for arg in "${ROLL_PARAMS[@]}" "$@"; do
    case "$arg" in
        -d|--directory|--directory=*) HAS_DIRECTORY=1 ;;
        -B|--database|--database=*) HAS_DATABASE=1 ;;
        -o|--overwrite-tables) HAS_OVERWRITE=1 ;;
    esac
done

## connect as root so the load has full privileges on the target schema
MYLOADER_ARGS=(--host=db --user=root --password="${MYSQL_ROOT_PASSWORD}")
[[ ${HAS_DATABASE} -eq 0 ]] && MYLOADER_ARGS+=(--database="${MYSQL_DATABASE}")
[[ ${HAS_DIRECTORY} -eq 0 ]] && MYLOADER_ARGS+=(--directory="${MYLOADER_INPUT_DIR}")
[[ ${HAS_OVERWRITE} -eq 0 ]] && MYLOADER_ARGS+=(--overwrite-tables)

"${ROLL_DIR}/bin/roll" cli myloader "${MYLOADER_ARGS[@]}" "${ROLL_PARAMS[@]}" "$@"
