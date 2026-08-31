#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Interactive prompts and styled output, all of it gum-backed.
##
## Every prompt in this file follows one rule: a value supplied by a flag or an environment variable
## wins, gum runs only when there is a terminal to run it in, and anything else is a hard error that
## names the flag which would have supplied the value. gum has no non-interactive mode - `gum choose`
## and `gum input` open /dev/tty directly and exit 1 when there is no terminal, and piping into them
## supplies options rather than an answer - so a prompt must never be reached to obtain a value that
## was not already resolvable without one. That is what makes roll drivable from a script, a CI job
## or an AI assistant.
##
## The plain messaging helpers in core.sh (fatal/error/warning/info/success) stay gum-free on
## purpose: they have to work in pipes and CI, where gum is neither present nor wanted.

## Minimum gum with the uniform exit-code contract: 0 chosen, 1 cancelled with ESC, 130 Ctrl-C.
ROLL_GUM_REQUIRE="0.14.0"

## Is there a terminal on both ends? gum needs one; nothing here may assume it.
function isInteractive() {
    [[ -t 0 && -t 1 ]]
}

## Called lazily by the wrappers below, never at startup: a non-interactive invocation of a command
## that happens not to prompt must keep working on a machine with no gum installed.
function assertGum() {
    if ! command -v gum >/dev/null 2>&1; then
        error "This prompt needs \`gum\`, which is not installed."
        >&2 echo ""
        >&2 echo "    macOS:          brew install gum"
        >&2 echo "    Debian/Ubuntu:  sudo mkdir -p /etc/apt/keyrings \\"
        >&2 echo "                      && curl -fsSL https://repo.charm.sh/apt/gpg.key \\"
        >&2 echo "                         | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg \\"
        >&2 echo "                      && echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \\"
        >&2 echo "                         | sudo tee /etc/apt/sources.list.d/charm.list \\"
        >&2 echo "                      && sudo apt update && sudo apt install gum"
        >&2 echo "    Fedora/RHEL:    sudo dnf install gum"
        >&2 echo "    Arch:           sudo pacman -S gum"
        >&2 echo "    Anywhere:       download a binary from https://github.com/charmbracelet/gum/releases"
        >&2 echo ""
        fatal "Install gum and try again, or supply the value non-interactively."
    fi

    local installed=""
    installed="$(gum --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)" || true

    if [[ -z "${installed}" ]]; then
        warning "Could not determine the installed gum version; continuing."
        return 0
    fi

    if ! test "$(version "${installed}")" -ge "$(version "${ROLL_GUM_REQUIRE}")"; then
        fatal "gum ${ROLL_GUM_REQUIRE} or newer is required (${installed} installed); please upgrade it."
    fi

    return 0
}

## Turn gum's exit status into a message and an exit. ESC is 1 and Ctrl-C is 130; both mean the user
## chose not to answer, and 130 is propagated so a caller in a pipeline sees a real interrupt.
function handleGumCancel() {
    local status="$1"
    local what="$2"

    if [[ "${status}" == "130" ]]; then
        >&2 echo ""
        error "Cancelled."
        exit 130
    fi

    error "No ${what} selected."
    exit 1
}

## Explain how to supply a value when there is no terminal to ask on.
function fatalNoTty() {
    local what="$1"
    local how="$2"

    error "Cannot prompt for ${what}: no terminal attached."
    fatal "Supply it non-interactively with ${how}."
}

## promptInput <varname> <how-to-supply> <prompt> [placeholder]
## Leaves the variable untouched when it already holds a value.
function promptInput() {
    local var="$1" how="$2" prompt="$3" placeholder="${4:-}"
    local current="" value="" status=0

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if ! isInteractive; then
        fatalNoTty "${prompt}" "${how}"
    fi

    assertGum
    value="$(gum input --prompt "${prompt} " --placeholder "${placeholder}")" || status=$?
    if [[ ${status} -ne 0 ]]; then
        handleGumCancel "${status}" "value"
    fi

    if [[ -z "${value}" ]]; then
        error "No value entered."
        exit 1
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}

## promptChoose <varname> <how-to-supply> <header> <option>...
function promptChoose() {
    local var="$1" how="$2" header="$3"
    shift 3
    local current="" value="" status=0

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if (( $# == 0 )); then
        fatal "promptChoose called with no options for ${var}."
    fi

    if ! isInteractive; then
        fatalNoTty "${header}" "${how}"
    fi

    assertGum
    value="$(gum choose --header "${header}" -- "$@")" || status=$?
    if [[ ${status} -ne 0 ]]; then
        handleGumCancel "${status}" "option"
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}

## promptConfirm <how-to-supply> <question>
## Returns 0 for yes and 1 for no, so it reads naturally in an if. Ctrl-C still exits 130.
function promptConfirm() {
    local how="$1" question="$2"
    local status=0

    if ! isInteractive; then
        fatalNoTty "confirmation" "${how}"
    fi

    assertGum
    gum confirm "${question}" || status=$?

    if [[ ${status} == "130" ]]; then
        >&2 echo ""
        error "Cancelled."
        exit 130
    fi

    return "${status}"
}

## promptPassword <varname> <how-to-supply> <prompt> [confirm-prompt]
## When a confirm prompt is given the two entries must match. The value is never echoed and never
## becomes a process argument.
function promptPassword() {
    local var="$1" how="$2" prompt="$3" confirm_prompt="${4:-}"
    local current="" value="" confirm="" status=0

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if ! isInteractive; then
        fatalNoTty "a password" "${how}"
    fi

    assertGum
    value="$(gum input --password --prompt "${prompt} ")" || status=$?
    if [[ ${status} -ne 0 ]]; then
        handleGumCancel "${status}" "password"
    fi

    if [[ -z "${value}" ]]; then
        error "Password cannot be empty."
        exit 1
    fi

    if [[ -n "${confirm_prompt}" ]]; then
        confirm="$(gum input --password --prompt "${confirm_prompt} ")" || status=$?
        if [[ ${status} -ne 0 ]]; then
            handleGumCancel "${status}" "password"
        fi
        if [[ "${value}" != "${confirm}" ]]; then
            fatal "Passwords do not match."
        fi
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}

## Styled boxes. gum renders them when there is a terminal to render into; otherwise the plain
## renderer from core.sh is used, so piped and CI output stays clean ASCII.
function styledBox() {
    local color="$1"
    shift

    if ! isInteractive || ! command -v gum >/dev/null 2>&1; then
        box "${color}" "$@"
        return 0
    fi

    local gum_color=""
    case "${color}" in
        1) gum_color="1" ;;
        2) gum_color="2" ;;
        *) gum_color="7" ;;
    esac

    printf '%s\n' "$@" | gum style \
        --border rounded \
        --border-foreground "${gum_color}" \
        --foreground "${gum_color}" \
        --padding "0 1" \
        --margin "0" || box "${color}" "$@"

    return 0
}
