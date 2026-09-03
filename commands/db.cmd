#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (ROLL_DB=0)."
fi

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  ## Do NOT re-invoke `roll db --help` here. `db` is on roll's ROLL_CMD_ANYARGS list, so roll's
  ## own parser stops at --help and passes it through to this script with ROLL_PARAMS empty -
  ## re-invoking roll lands right back on this branch and forks until killed.
  source "${ROLL_DIR}/commands/usage.cmd"
fi

## load connection information for the mysql service
DB_CONTAINER=$(roll env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service."
fi

eval "$(
    docker container inspect ${DB_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQL_"
)"

## MariaDB 11 images dropped the mysql*/mysqldump compatibility symlinks and only ship
## mariadb/mariadb-dump; probe once per invocation and use whichever pair is present, so both
## MariaDB 11 and MySQL/MariaDB 10.x images keep working. Sets RESOLVED_DB_BIN on success.
resolveDbBinary() {
    local preferred="$1" fallback="$2" bin

    bin="$("${ROLL_DIR}/bin/roll" env exec -T db sh -c "command -v ${preferred} || command -v ${fallback}" 2>/dev/null)" || true
    if [[ ! ${bin} ]]; then
        local image
        image="$(docker container inspect "${DB_CONTAINER}" --format '{{.Config.Image}}' 2>/dev/null)" || true
        fatal "Neither \"${preferred}\" nor \"${fallback}\" was found in the db container (image: ${image:-unknown})."
    fi

    RESOLVED_DB_BIN="${bin##*/}"
}

## sub-command execution
case "${ROLL_PARAMS[0]}" in
    connect)
        resolveDbBinary mariadb mysql
        "${ROLL_DIR}/bin/roll" env exec db \
            "${RESOLVED_DB_BIN}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --database="${MYSQL_DATABASE}" "${ROLL_PARAMS[@]:1}" "$@"
        ;;
    import)
        resolveDbBinary mariadb mysql
        LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`/DEFINER=CURRENT_USER/g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "${ROLL_DIR}/bin/roll" env exec -T db \
            "${RESOLVED_DB_BIN}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --database="${MYSQL_DATABASE}" "${ROLL_PARAMS[@]:1}" "$@"
        ;;
    dump)
        resolveDbBinary mariadb-dump mysqldump
            "${ROLL_DIR}/bin/roll" env exec -T db \
            "${RESOLVED_DB_BIN}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" "${ROLL_PARAMS[@]:1}" "$@"
        ;;
    *)
        fatal "The command \"${ROLL_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
