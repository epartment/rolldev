#!/usr/bin/env bash
# Parse every command, help and util file with the running bash.
#
# Worth its own step because two classes of defect are invisible to both ShellCheck and Ubuntu CI:
#
#   1. bash 3.2 mis-parses an apostrophe inside a heredoc nested in $( ), even when the heredoc
#      delimiter is quoted. backup.help and status.help both shipped broken this way - `roll backup
#      --help` and `roll status --help` exited 2 on macOS - while parsing cleanly under bash 5.
#   2. a .cmd that re-invokes `roll <itself> --help` recurses forever, because commands on
#      ROLL_CMD_ANYARGS receive --help directly instead of roll rendering it. restore, restore-full
#      and duplicate each did this, forking until killed.
#
# Run this under the system bash on macOS (bash 3.2) for the first check to mean anything.
set -eu

ROLL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROLL_DIR}"

failed=0

echo "bash ${BASH_VERSION} syntax check"
for file in bin/roll commands/*.cmd commands/*/*.cmd commands/*.help commands/*/*.help utils/*.sh; do
    [[ -e "${file}" ]] || continue
    if ! bash -n "${file}" 2>/dev/null; then
        echo "  FAIL  ${file}"
        bash -n "${file}" 2>&1 | sed 's/^/        /'
        failed=$((failed + 1))
    fi
done

echo "self-referential --help check"
for file in commands/*.cmd commands/*/*.cmd; do
    [[ -e "${file}" ]] || continue
    name="${file##*/}"
    name="${name%.cmd}"
    ## Only commands on ROLL_CMD_ANYARGS receive --help themselves; for everything else bin/roll
    ## renders the help and the inner call terminates, so it is not a defect there.
    case " $(sed -n 's/.*ROLL_CMD_ANYARGS=(\(.*\)).*/\1/p' bin/roll) " in
        *" ${name} "*) ;;
        *) continue ;;
    esac
    if grep -qE "^[[:space:]]*roll[[:space:]]+${name}[[:space:]]+(--help|-h)" "${file}"; then
        echo "  FAIL  ${file} re-invokes 'roll ${name} --help', which recurses forever"
        echo "        source \"\${ROLL_DIR}/commands/usage.cmd\" instead"
        failed=$((failed + 1))
    fi
done

if [[ ${failed} -ne 0 ]]; then
    echo "${failed} file(s) failed."
    exit 1
fi

echo "All files parse and no command re-invokes its own help."
