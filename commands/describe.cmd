#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## `describe` is on roll's ROLL_CMD_ANYARGS list (needed so --format reaches this script - also
## true when reached via `roll env describe`, since `env` is already anyargs), so roll's own
## parser stops at the first dash-prefixed argument and leaves it in "$@". Parse flags from "$@",
## not ROLL_PARAMS.
DESCRIBE_FORMAT="human"
describeArgs=("$@")
i=0
while [[ $i -lt ${#describeArgs[@]} ]]; do
    case "${describeArgs[$i]}" in
        -h|--help)
            ## Do NOT re-invoke `roll describe --help` here - describe is on ROLL_CMD_ANYARGS, so
            ## re-invoking roll lands right back on this branch and forks until killed.
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            DESCRIBE_FORMAT="${describeArgs[$i]#*=}"
            ;;
        --format)
            i=$((i + 1))
            DESCRIBE_FORMAT="${describeArgs[$i]:-}"
            ;;
        *)
            fatal "Unsupported argument ${describeArgs[$i]}"
            ;;
    esac
    i=$((i + 1))
done

if [[ "${DESCRIBE_FORMAT}" != "human" && "${DESCRIBE_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${DESCRIBE_FORMAT}' (expected: human, json)"
fi

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

# Colors
GREEN='\033[32m'
RED='\033[31m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Ask Compose once which containers this project has and what state each is in, keyed by service
# label rather than by a reconstructed container name. Resolving each service individually meant a
# full roll re-entry per row - config load plus a compose call - which took ~9s on a nine-service
# project against ~1.3s for the whole command before.
ROLL_DESCRIBE_SERVICES=()
ROLL_DESCRIBE_STATES=()
while IFS='=' read -r describe_service describe_state; do
    [[ -z "${describe_service}" ]] && continue
    ROLL_DESCRIBE_SERVICES+=("${describe_service}")
    ROLL_DESCRIBE_STATES+=("${describe_state}")
done < <(docker ps -a \
    --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
    --format '{{.Label "com.docker.compose.service"}}={{.State}}' 2>/dev/null)

# Get container status (returns "running" or "stopped")
get_status_text() {
    local service=$1
    local i=0

    while [[ $i -lt ${#ROLL_DESCRIBE_SERVICES[@]} ]]; do
        if [[ "${ROLL_DESCRIBE_SERVICES[$i]}" == "$service" ]]; then
            if [[ "${ROLL_DESCRIBE_STATES[$i]}" == "running" ]]; then
                echo "running"
            else
                echo "stopped"
            fi
            return 0
        fi
        i=$((i + 1))
    done

    echo "stopped"
}

# Print status with color
print_status() {
    local status=$1
    if [[ "$status" == "running" ]]; then
        printf "${GREEN}%-8s${NC}" "running"
    else
        printf "${RED}%-8s${NC}" "stopped"
    fi
}

# Table dimensions
W=95

# Horizontal lines
line_top() {
    printf "${CYAN}┌"
    printf '─%.0s' $(seq 1 $((W-2)))
    printf "┐${NC}\n"
}

line_mid() {
    printf "${CYAN}├"
    printf '─%.0s' $(seq 1 14)
    printf "┼"
    printf '─%.0s' $(seq 1 10)
    printf "┼"
    printf '─%.0s' $(seq 1 45)
    printf "┼"
    printf '─%.0s' $(seq 1 22)
    printf "┤${NC}\n"
}

line_bot() {
    printf "${CYAN}└"
    printf '─%.0s' $(seq 1 14)
    printf "┴"
    printf '─%.0s' $(seq 1 10)
    printf "┴"
    printf '─%.0s' $(seq 1 45)
    printf "┴"
    printf '─%.0s' $(seq 1 22)
    printf "┘${NC}\n"
}

# Header row
header_row() {
    printf "${CYAN}│${NC} ${BOLD}%-12s${NC} ${CYAN}│${NC} ${BOLD}%-8s${NC} ${CYAN}│${NC} ${BOLD}%-43s${NC} ${CYAN}│${NC} ${BOLD}%-20s${NC} ${CYAN}│${NC}\n" "$1" "$2" "$3" "$4"
}

# Data row with status
data_row() {
    local name=$1
    local status=$2
    local url=$3
    local info=$4
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} " "$name"
    print_status "$status"
    printf " ${CYAN}│${NC} %-43s ${CYAN}│${NC} %-20s ${CYAN}│${NC}\n" "$url" "$info"
}

# Sub row (continuation, no status)
sub_row() {
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} %-8s ${CYAN}│${NC} ${DIM}%-43s${NC} ${CYAN}│${NC} %-20s ${CYAN}│${NC}\n" "" "" "$1" "$2"
}

# Info row (spans columns)
info_row() {
    printf "${CYAN}│${NC} ${BOLD}%-12s${NC} ${CYAN}│${NC} %-76s ${CYAN}│${NC}\n" "$1" "$2"
}

# Text row (spans columns, for URLs)
text_row() {
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} %-76s ${CYAN}│${NC}\n" "" "$1"
}

# Collects one service row for --format json (name/status/url/info only - never the sub_row
# credential hints such as the "magento/magento" default login, which are never passed here).
jsonServiceNames=()
jsonServiceStates=()
jsonServiceUrls=()
jsonServiceInfos=()

# Renders a service row: the human table when human, or captures it for json when json. Single
# call site per service, so status is looked up (from the cached arrays above, no docker call)
# exactly once either way.
service_row() {
    local name=$1
    local status=$2
    local url=$3
    local info=$4
    if [[ "${DESCRIBE_FORMAT}" == "json" ]]; then
        jsonServiceNames+=("${name}")
        jsonServiceStates+=("${status}")
        jsonServiceUrls+=("${url}")
        jsonServiceInfos+=("${info}")
    else
        data_row "${name}" "${status}" "${url}" "${info}"
    fi
}

PROJECT_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}"

if [[ "${DESCRIBE_FORMAT}" != "json" ]]; then
    echo ""

    # Header box
    line_top
    printf "${CYAN}│${NC} ${BOLD}Project:${NC} %-83s ${CYAN}│${NC}\n" "${ROLL_ENV_NAME} ${ROLL_ENV_PATH}"
    printf "${CYAN}│${NC} ${BOLD}Domain:${NC}  %-83s ${CYAN}│${NC}\n" "${PROJECT_URL}"
    printf "${CYAN}│${NC} ${BOLD}Type:${NC}    %-83s ${CYAN}│${NC}\n" "${ROLL_ENV_TYPE} PHP ${PHP_VERSION} | Node ${NODE_VERSION}"
    printf "${CYAN}│${NC} ${BOLD}Router:${NC}  %-83s ${CYAN}│${NC}\n" "traefik"
    line_mid

    # Table header
    header_row "SERVICE" "STATUS" "URL/PORT" "INFO"
    line_mid
fi

# Services
service_row "nginx" "$(get_status_text nginx)" "${PROJECT_URL}" "${ROLL_ENV_TYPE}"
[[ "${DESCRIBE_FORMAT}" != "json" ]] && sub_row "InDocker: nginx:80,443" "Server: nginx-fpm"

service_row "php-fpm" "$(get_status_text php-fpm)" "InDocker: php-fpm:9000" "PHP ${PHP_VERSION}"

if [[ "${ROLL_XDEBUG:-0}" == "1" ]] || [[ "${PHP_XDEBUG_3:-0}" == "1" ]]; then
    service_row "php-debug" "$(get_status_text php-debug)" "InDocker: php-debug:9000" "Xdebug 3"
fi

if [[ "${ROLL_DB:-1}" == "1" ]]; then
    DB_TYPE="${DB_DISTRIBUTION:-mariadb}:${DB_DISTRIBUTION_VERSION}"
    service_row "db" "$(get_status_text db)" "InDocker: db:3306" "${DB_TYPE}"
    ## Default local dev credentials hint - human output only, never part of the json output.
    [[ "${DESCRIBE_FORMAT}" != "json" ]] && sub_row "" "magento/magento"
fi

if [[ "${ROLL_REDIS:-0}" == "1" ]]; then
    service_row "redis" "$(get_status_text redis)" "InDocker: redis:6379" "Redis ${REDIS_VERSION}"
fi

if [[ "${ROLL_REDISINSIGHT:-0}" == "1" ]]; then
    service_row "redisinsight" "$(get_status_text redisinsight)" "https://insight.${TRAEFIK_DOMAIN}" ""
fi

if [[ "${ROLL_ELASTICSEARCH:-0}" == "1" ]]; then
    service_row "elasticsearch" "$(get_status_text elasticsearch)" "InDocker: elasticsearch:9200" "ES ${ELASTICSEARCH_VERSION}"
fi

if [[ "${ROLL_OPENSEARCH:-0}" == "1" ]]; then
    service_row "opensearch" "$(get_status_text opensearch)" "InDocker: opensearch:9200" "OS ${OPENSEARCH_VERSION}"
fi

if [[ "${ROLL_RABBITMQ:-0}" == "1" ]]; then
    service_row "rabbitmq" "$(get_status_text rabbitmq)" "https://rabbitmq.${TRAEFIK_DOMAIN}" "Management UI"
fi

if [[ "${ROLL_VARNISH:-0}" == "1" ]]; then
    service_row "varnish" "$(get_status_text varnish)" "InDocker: varnish:80" ""
fi

if docker ps -a --format '{{.Names}}' | grep -q "${ROLL_ENV_NAME}-mailhog-1"; then
    service_row "mailhog" "$(get_status_text mailhog)" "https://mailhog.${TRAEFIK_DOMAIN}" "Mail catcher"
fi

if [[ "${DESCRIBE_FORMAT}" == "json" ]]; then
    ## Network this project's containers are attached to (dev.roll.environment.name label,
    ## environments/includes/networks.base.yml); one lookup, not a per-service call.
    projectNetwork=$(docker network ls --filter "label=dev.roll.environment.name=${ROLL_ENV_NAME}" --format '{{.Name}}' 2>/dev/null | head -n1)

    runningContainerCount=0
    for describe_state in "${ROLL_DESCRIBE_STATES[@]}"; do
        [[ "${describe_state}" == "running" ]] && runningContainerCount=$((runningContainerCount + 1))
    done

    out="{"
    out+="\"name\":\"$(jsonEscape "${ROLL_ENV_NAME}")\","
    out+="\"type\":\"$(jsonEscape "${ROLL_ENV_TYPE}")\","
    out+="\"dir\":\"$(jsonEscape "${ROLL_ENV_PATH}")\","
    out+="\"url\":\"$(jsonEscape "${PROJECT_URL}")\","
    out+="\"network\":\"$(jsonEscape "${projectNetwork}")\","
    out+="\"containers\":${runningContainerCount},"
    out+="\"services\":["
    i=0
    while [[ $i -lt ${#jsonServiceNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{"
        out+="\"name\":\"$(jsonEscape "${jsonServiceNames[$i]}")\","
        out+="\"status\":\"$(jsonEscape "${jsonServiceStates[$i]}")\","
        out+="\"url\":\"$(jsonEscape "${jsonServiceUrls[$i]}")\","
        out+="\"info\":\"$(jsonEscape "${jsonServiceInfos[$i]}")\""
        out+="}"
        i=$((i + 1))
    done
    out+="]}"
    printf '%s\n' "${out}"
    exit 0
fi

line_mid

# Project URLs
if [[ -f "${ROLL_ENV_PATH}/.roll/stores.json" ]] && command -v jq &> /dev/null; then
    info_row "Project URLs" ""

    # Main URL
    text_row "${PROJECT_URL}"

    # Store URLs
    jq -r '.stores | keys[]' "${ROLL_ENV_PATH}/.roll/stores.json" 2>/dev/null | while read hostname; do
        text_row "https://${hostname}"
    done
fi

line_bot
echo ""
