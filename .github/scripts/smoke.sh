#!/usr/bin/env bash
#
# Docker-free smoke test for the `roll` CLI.
#
# Exercises commands that need neither a running Docker daemon nor an existing project checkout,
# so platform-specific regressions (bash 3.2 syntax, BSD vs GNU tool differences) surface without
# needing the full Docker-backed environment stack. Run from CI (macos-latest + ubuntu-latest) or
# locally.
#
# Usage: smoke.sh [bash32]
#   (no argument)  invoke roll natively, i.e. via its own #!/usr/bin/env bash shebang
#   bash32         invoke roll explicitly under /bin/bash, to exercise bash 3.2.57 on macOS rather
#                  than whatever newer bash happens to be first on PATH

set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROLL_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

MODE="${1:-native}"

case "${MODE}" in
  bash32)
    ROLL_BIN=(/bin/bash "${ROLL_DIR}/bin/roll")
    ;;
  native)
    ROLL_BIN=("${ROLL_DIR}/bin/roll")
    ;;
  *)
    >&2 echo "Usage: $0 [bash32]"
    exit 1
    ;;
esac

run() {
  echo "+ ${ROLL_BIN[*]} $*"
  "${ROLL_BIN[@]}" "$@"
}

run version
run config schema >/dev/null
run registry validate
run registry categories >/dev/null
run registry paths >/dev/null

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roll-smoke.XXXXXX")"
cleanup() {
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

(
  cd -- "${TMP_DIR}"
  "${ROLL_BIN[@]}" env-init smoketest magento2
  "${ROLL_BIN[@]}" config validate
)

echo "Smoke test passed (${MODE} mode)."
