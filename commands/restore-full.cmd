#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## restore-full is restore with --include-source preset. The two were near-identical copies -
## eleven of their sixteen functions were byte-identical - and the shared half now lives in
## utils/backup.sh while the half unique to a full restore lives in restore.cmd behind that flag.
##
## Kept as its own command because the name is the documented interface and scripts use it.
ROLL_PARAMS=("--include-source" "${ROLL_PARAMS[@]}")
source "${ROLL_DIR}/commands/restore.cmd"
