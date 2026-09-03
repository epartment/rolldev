#!/usr/bin/env bash
# Asserts the non-interactive contract of utils/interact.sh: a value supplied by flag or env wins
# without ever reaching gum, and a prompt that cannot be answered fails naming the flag that would
# have answered it. This is the half of the interaction layer that automation depends on, and the
# half a TTY-less CI run can actually verify.
set -u
ROLL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROLL_DIR
. "$ROLL_DIR/utils/core.sh"
. "$ROLL_DIR/utils/interact.sh"

pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }

echo "== isInteractive with stdin from /dev/null =="
if isInteractive; then r=interactive; else r=non-interactive; fi
check "reports non-interactive" "$r" "non-interactive"

echo "== preset value short-circuits, gum never invoked =="
# Remove gum from PATH entirely: if the wrapper touches gum at all, this explodes.
ORIG_PATH="$PATH"
export PATH=/usr/bin:/bin
MYVAR="already-set"
out=$(promptInput MYVAR "--name" "Name:" 2>&1); st=$?
check "promptInput exit status" "$st" "0"
check "promptInput left value intact" "$MYVAR" "already-set"

CHOICE="magento2"
promptChoose CHOICE "--type" "Pick a type" php laravel magento2 >/dev/null 2>&1; st=$?
check "promptChoose exit status" "$st" "0"
check "promptChoose left value intact" "$CHOICE" "magento2"

PW="hunter2"
promptPassword PW "--encrypt=" "Password:" >/dev/null 2>&1; st=$?
check "promptPassword exit status" "$st" "0"
check "promptPassword left value intact" "$PW" "hunter2"
export PATH="$ORIG_PATH"

echo "== no preset + no tty = hard error naming the flag =="
UNSET_A=""
out=$( (promptInput UNSET_A "--name <value>" "Name:") 2>&1 ); st=$?
check "promptInput exits 1" "$st" "1"
case "$out" in *"--name <value>"*) r=yes;; *) r=no;; esac
check "promptInput names the flag" "$r" "yes"

UNSET_B=""
out=$( (promptChoose UNSET_B "--type <type>" "Pick a type" php laravel) 2>&1 ); st=$?
check "promptChoose exits 1" "$st" "1"
case "$out" in *"--type <type>"*) r=yes;; *) r=no;; esac
check "promptChoose names the flag" "$r" "yes"

out=$( (promptConfirm "--force" "Overwrite?") 2>&1 ); st=$?
check "promptConfirm exits 1" "$st" "1"
case "$out" in *"--force"*) r=yes;; *) r=no;; esac
check "promptConfirm names the flag" "$r" "yes"

UNSET_C=""
out=$( (promptPassword UNSET_C "--encrypt=<password>" "Password:") 2>&1 ); st=$?
check "promptPassword exits 1" "$st" "1"
case "$out" in *"--encrypt=<password>"*) r=yes;; *) r=no;; esac
check "promptPassword names the flag" "$r" "yes"

echo "== boxes fall back to plain renderer with no tty =="
out=$(styledBox 2 "hello world" 2>&1)
case "$out" in *"| hello world |"*) r=plain;; *) r=other;; esac
check "styledBox uses plain box" "$r" "plain"

echo "== survives set -e =="
( set -e; styledBox 7 "x" >/dev/null; MYV=preset; promptInput MYV "--x" "X:" >/dev/null; echo ok ) >/dev/null 2>&1
check "no premature exit under set -e" "$?" "0"

echo ""
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
