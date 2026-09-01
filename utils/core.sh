#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## global service containers to be connected with the project docker network
DOCKER_PEERED_SERVICES=("traefik" "tunnel" "mailhog")

## messaging functions
function success {
  >&2 printf "\033[32mSUCCESS\033[0m: %s\n" "$*"
}

function info {
  >&2 printf "\033[33mINFO\033[0m: %s\n" "$*"
}

function warning {
  >&2 printf "\033[33mWARNING\033[0m: %s\n" "$*"
}

function error {
  >&2 printf "\033[31mERROR\033[0m: %s\n" "$*"
}

function fatal {
  error "$@"
  exit 1
}

## draw a box around the given lines, with the text rendered in the given tput setaf color
function box() {
  local color="$1"; shift
  local s=("$@") b w use_tput=0

  # only enable colors if we have a tty and TERM is set (and not "dumb")
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] && command -v tput >/dev/null 2>&1; then
    use_tput=1
  fi

  for l in "${s[@]}"; do
    ((w < ${#l})) && { b="$l"; w="${#l}"; }
  done

  ((use_tput)) && tput setaf 3
  echo " -${b//?/-}-
| ${b//?/ } |"

  for l in "${s[@]}"; do
    if ((use_tput)); then
      printf '| %s%*s%s |\n' "$(tput setaf "$color")" "-$w" "$l" "$(tput setaf 3)"
    else
      printf '| %*s |\n' "-$w" "$l"
    fi
  done

  echo "| ${b//?/ } |
 -${b//?/-}-"
  ((use_tput)) && tput sgr 0

  return 0
}

function boxinfo() {
  box 7 "$@"
}

function boxsuccess() {
  box 2 "$@"
}

function boxerror() {
  box 1 "$@"
}

function version {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

## capitalize the first letter of a string; bash 3.2 compatible
function capitalize() {
  local s="$1"
  printf '%s%s' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"
}

## determines if value is present in an array; returns 0 if element is present
## in array, otherwise returns 1
##
## usage: containsElement <needle> <haystack>
##
function containsElement {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

## verify docker is running
function assertDockerRunning {
  if ! docker system info >/dev/null 2>&1; then
    fatal "Docker does not appear to be running. Please start Docker."
  fi
}

## methods to peer global services requiring network connectivity with project networks
function connectPeeredServices {
  for svc in "${DOCKER_PEERED_SERVICES[@]}"; do
    echo "Connecting ${svc} to $1 network"
    (docker network connect "$1" ${svc} 2>&1| grep -v 'already exists in network') || true
  done
}

function disconnectPeeredServices {
  for svc in "${DOCKER_PEERED_SERVICES[@]}"; do
    echo "Disconnecting ${svc} from $1 network"
    (docker network disconnect "$1" ${svc} 2>&1| grep -v 'is not connected') || true
  done
}

# Probe the registry that `svc pull` actually needs, with a 3-second timeout.
# Accept any HTTP response as proof of reachability (even 401 proves we reached the server).
# Do not use -f so 401 is treated as successful connection.
function isOnline() {
  if curl -s -m 3 -o /dev/null "https://ghcr.io/v2/" 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

## escape a raw string for embedding as a JSON string value; the caller supplies the
## surrounding quotes. bash 3.2 safe (pattern substitution only, no external tools).
## usage: printf '"%s"' "$(jsonEscape "$rawValue")"
function jsonEscape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "$raw"
}

## cross-platform sed in-place editing function
## works on both macOS (BSD sed) and Linux (GNU sed)
function sed_inplace() {
    local pattern="$1"
    local file="$2"
    local backup_ext="${3:-.bak}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS (BSD sed) - requires backup extension
        sed -i "$backup_ext" "$pattern" "$file"
    else
        # Linux (GNU sed) - backup extension is optional
        sed -i"$backup_ext" "$pattern" "$file"
    fi
    
    # Remove backup file if it exists and we used .bak extension
    if [[ "$backup_ext" == ".bak" && -f "${file}${backup_ext}" ]]; then
        rm -f "${file}${backup_ext}"
    fi
}
## Hand a database URI to TablePlus without putting it in the process list.
##
## The URI carries the database password, and `open "$uri" -a TablePlus` makes it an argument, so
## anything able to read `ps` can see it for as long as the call lasts - that is finding H2 against
## the internal command pack, where the URI holds real staging and production credentials.
##
## osascript reads its script from stdin, so only "osascript -" appears in the process list.
## `open location` routes by URL scheme, which is what TablePlus registers itself for.
function openInTablePlus() {
  local uri="$1"
  local escaped

  ## AppleScript string literals take the same escapes as C: backslash first, then quote
  escaped="${uri//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"

  if printf 'open location "%s"\n' "${escaped}" | osascript - >/dev/null 2>&1; then
    return 0
  fi

  ## Falling back to `open` puts the password in argv, so say so rather than exposing it silently.
  warning "Could not hand the connection to TablePlus via osascript; falling back to \`open\`,"
  warning "which briefly exposes the database password in the process list."
  open "${uri}" -a "${TABLEPLUS_APP:-TablePlus}"
}
