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

## Strips the ENCRYPTION table option and remaps utf8mb4_0900_* collations in mydumper schema
## files. MySQL 8 emits both, MariaDB rejects them, and only the schema files carry them — data
## files are never touched.
normalizeMyloaderSchemaDdl() {
    local dump_dir="$1"

    if [[ ! -d "${dump_dir}" ]]; then
        fatal "Dump directory \"${dump_dir}\" does not exist; cannot normalize schema DDL."
    fi

    local had_nullglob=0
    shopt -q nullglob && had_nullglob=1
    shopt -s nullglob
    local schema_files=("${dump_dir}"/*-schema*.sql)
    [[ ${had_nullglob} -eq 0 ]] && shopt -u nullglob

    if [[ ${#schema_files[@]} -eq 0 ]]; then
        warning "No *-schema*.sql files found in \"${dump_dir}\"; nothing to normalize."
        return 0
    fi

    local file
    for file in "${schema_files[@]}"; do
        sed_inplace "s/ ENCRYPTION='N'//g; s/ENCRYPTION='N'//g; s/utf8mb4_0900_[a-zA-Z0-9_]*/utf8mb4_general_ci/g" "${file}"
    done

    info "Normalized schema DDL in ${#schema_files[@]} file(s) under \"${dump_dir}\" for MariaDB compatibility."
}

## inject connection/location defaults unless the caller already supplied them; also pull
## --normalize-source-ddl out of the args (myloader itself does not know it) and capture the
## effective directory so it can be normalized before myloader runs
MYLOADER_DIRECTORY="${MYLOADER_INPUT_DIR}"
HAS_DIRECTORY=0
HAS_DATABASE=0
NORMALIZE_SOURCE_DDL=0
FILTERED_ARGS=()
ALL_ARGS=("${ROLL_PARAMS[@]}" "$@")
SKIP_NEXT=0
for arg in "${ALL_ARGS[@]}"; do
    if [[ ${SKIP_NEXT} -eq 1 ]]; then
        SKIP_NEXT=0
        MYLOADER_DIRECTORY="${arg}"
        FILTERED_ARGS+=("${arg}")
        continue
    fi

    case "$arg" in
        --normalize-source-ddl)
            NORMALIZE_SOURCE_DDL=1
            continue
            ;;
        -d|--directory)
            HAS_DIRECTORY=1
            SKIP_NEXT=1
            ;;
        --directory=*)
            HAS_DIRECTORY=1
            MYLOADER_DIRECTORY="${arg#*=}"
            ;;
        -B|--database|--database=*)
            HAS_DATABASE=1
            ;;
    esac

    FILTERED_ARGS+=("${arg}")
done

if [[ ${NORMALIZE_SOURCE_DDL} -eq 1 ]]; then
    ## --directory is a path inside the container, but normalization runs on the host. The project
    ## root is mounted at /var/www/html, so a relative path maps straight across and an absolute
    ## one has to have that prefix stripped; anything else is outside the mount and unreachable.
    NORMALIZE_DIR="${MYLOADER_DIRECTORY}"
    case "${NORMALIZE_DIR}" in
        /var/www/html/*) NORMALIZE_DIR="${ROLL_ENV_PATH}/${NORMALIZE_DIR#/var/www/html/}" ;;
        /var/www/html)   NORMALIZE_DIR="${ROLL_ENV_PATH}" ;;
        /*)              fatal "--normalize-source-ddl needs a dump directory inside the project (got \"${NORMALIZE_DIR}\"); it rewrites the files on the host." ;;
        *)               NORMALIZE_DIR="${ROLL_ENV_PATH}/${NORMALIZE_DIR}" ;;
    esac
    normalizeMyloaderSchemaDdl "${NORMALIZE_DIR}"
fi

## Inject the connection details (read from the db container) and location defaults; all other
## flags are passed straight through to myloader.
MYLOADER_ARGS=(--host=db --user=root --password="${MYSQL_ROOT_PASSWORD}")
[[ ${HAS_DATABASE} -eq 0 ]] && MYLOADER_ARGS+=(--database="${MYSQL_DATABASE}")
[[ ${HAS_DIRECTORY} -eq 0 ]] && MYLOADER_ARGS+=(--directory="${MYLOADER_INPUT_DIR}")

## Capture myloader's output (pipefail in a subshell, so the pipeline reports myloader's exit
## code rather than tee's) so a failed run without --normalize-source-ddl can be diagnosed: MySQL
## 8 dumps loaded into MariaDB abort on the ENCRYPTION table option or utf8mb4_0900_* collations,
## and myloader's own message for both is an unhelpful "Trace/breakpoint trap (core dumped)".
MYLOADER_LOG="$(mktemp)"
trap 'rm -f "${MYLOADER_LOG}"' EXIT
MYLOADER_EXIT=0
(set -o pipefail; "${ROLL_DIR}/bin/roll" cli myloader "${MYLOADER_ARGS[@]}" "${FILTERED_ARGS[@]}" 2>&1 | tee "${MYLOADER_LOG}") || MYLOADER_EXIT=$?

if [[ ${MYLOADER_EXIT} -ne 0 && ${NORMALIZE_SOURCE_DDL} -eq 0 ]]; then
    if grep -qE "ERROR 1911|Unknown option 'ENCRYPTION'" "${MYLOADER_LOG}"; then
        error "myloader failed: the dump's schema uses the ENCRYPTION table option, which MariaDB does not support."
        info "Retry with --normalize-source-ddl to strip it automatically."
    elif grep -qE "ERROR 1273|Unknown collation|utf8mb4_0900" "${MYLOADER_LOG}"; then
        error "myloader failed: the dump's schema uses a utf8mb4_0900_* collation, which MariaDB does not support."
        info "Retry with --normalize-source-ddl to remap it automatically."
    elif grep -q "Trace/breakpoint trap" "${MYLOADER_LOG}"; then
        error "myloader crashed (Trace/breakpoint trap). This is the typical symptom of restoring a MySQL 8 dump into MariaDB: the ENCRYPTION table option or a utf8mb4_0900_* collation in the schema is unsupported by MariaDB."
        info "Retry with --normalize-source-ddl to strip/remap these automatically."
    fi
fi

exit "${MYLOADER_EXIT}"
