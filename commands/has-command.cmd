#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Feature-detection primitive for scripts: exit 0 if the named command resolves through the
## registry (any of the four search paths, including RECLU), exit 1 if it does not. No output
## either way, so a caller can use it purely for its exit code.
##
## "Not found" is an expected, silent outcome here, not a failure: disable bin/roll ERR trap so a
## non-matching lookup does not print an error before this exits 1.
trap '' ERR

if [[ ${#ROLL_PARAMS[@]} -eq 0 ]]; then
    exit 1
fi

initializeRegistry
isCommandRegistered "${ROLL_PARAMS[0]}"
exit $?
