#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_REDIS:-1} -eq 0 && ${ROLL_DRAGONFLY:-1} -eq 0 ]]; then
  fatal "Redis nor Dragonfly environment is not used (ROLL_REDIS=0|ROLL_DRAGONFLY=0)."
fi

## Bare `roll redis` opens a session, so this cannot key on an empty ROLL_PARAMS the way db/env/svc
## do; --help arrives in "$@" because redis is on ROLL_CMD_ANYARGS, which is why it never used to
## reach this branch at all.
if [[ "${ROLL_PARAMS[0]:-}" == "help" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  ## Do NOT re-invoke `roll redis --help` here. `redis` is on roll's ROLL_CMD_ANYARGS list, so roll's
  ## own parser stops at --help and passes it through to this script with ROLL_PARAMS empty -
  ## re-invoking roll lands right back on this branch and forks until killed.
  source "${ROLL_DIR}/commands/usage.cmd"
fi

## load connection information for the redis service
REDIS_CONTAINER=$(roll env ps -q redis)
if [[ ! ${REDIS_CONTAINER} ]]; then
    fatal "No container found for redis service."
fi

"${ROLL_DIR}/bin/roll" env exec redis redis-cli "${ROLL_PARAMS[@]}" "$@"
