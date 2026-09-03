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

  # The version overview reads the catalog and the project config only, so it needs no network
  echo "+ config versions"
  "${ROLL_BIN[@]}" config versions >/dev/null

  # Setting a version non-interactively must rewrite the pin in place. The registry lookup that
  # would warn about an unknown tag is best-effort, so this passes with or without network access.
  echo "+ config version php 8.2"
  "${ROLL_BIN[@]}" config version php 8.2 >/dev/null 2>&1
  if ! grep -q '^PHP_VERSION=8.2$' .env.roll; then
    >&2 echo "FAIL: roll config version did not write PHP_VERSION=8.2"
    exit 1
  fi
  if [[ "$(grep -c '^PHP_VERSION=' .env.roll)" != "1" ]]; then
    >&2 echo "FAIL: roll config version left more than one PHP_VERSION line"
    exit 1
  fi

  # Same again, so the "nothing to change" path is exercised and stays a success
  "${ROLL_BIN[@]}" config version php 8.2 >/dev/null 2>&1

  # A commented pin is replaced rather than duplicated (magento2's init.env ships one)
  echo "+ config version opensearch 2.19"
  "${ROLL_BIN[@]}" config version opensearch 2.19 >/dev/null 2>&1
  if [[ "$(grep -c '^#*[[:space:]]*OPENSEARCH_VERSION=' .env.roll)" != "1" ]]; then
    >&2 echo "FAIL: roll config version duplicated the commented OPENSEARCH_VERSION line"
    exit 1
  fi

  # With no terminal, the service prompt must fail naming the non-interactive form, and write
  # nothing - this is the contract automation depends on
  echo "+ config version (no tty)"
  if out="$("${ROLL_BIN[@]}" config version 2>&1 </dev/null)"; then
    >&2 echo "FAIL: roll config version succeeded with no terminal and no arguments"
    exit 1
  fi
  case "${out}" in
    *"roll config version <service> <version>"*) ;;
    *)
      >&2 echo "FAIL: roll config version did not name its non-interactive form"
      exit 1
      ;;
  esac

  echo "+ config version nosuchservice"
  if "${ROLL_BIN[@]}" config version nosuchservice 1.0 >/dev/null 2>&1; then
    >&2 echo "FAIL: roll config version accepted an unknown service"
    exit 1
  fi
)

"$(dirname "$0")/test-syntax.sh"
"$(dirname "$0")/test-interact.sh" < /dev/null

echo "Smoke test passed (${MODE} mode)."
