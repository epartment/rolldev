#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## `image-cleanup` is on roll's ROLL_CMD_ANYARGS list so its flags reach this script, which means
## roll's own parser stops at the first dash-prefixed argument and leaves ROLL_PARAMS empty.
## Parse flags from "$@", and render help by sourcing usage.cmd - re-invoking
## `roll image-cleanup --help` would land right back here and fork until killed.
CLEANUP_DRY_RUN=0

if (( ${#ROLL_PARAMS[@]} > 0 )); then
    fatal "Unsupported argument ${ROLL_PARAMS[0]}"
fi

while (( "$#" )); do
    case "$1" in
        -h|--help)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --dry-run)
            CLEANUP_DRY_RUN=1
            ;;
        *)
            fatal "Unsupported argument $1"
            ;;
    esac
    shift
done

assertDockerRunning

## ROLL_IMAGE_REPOSITORY decides which images are roll's; this command is host-wide, so only the
## global configuration applies, loaded in the same order loadRollConfig uses
initConfigSchema
for globalConfig in "${ROLL_HOME_DIR}/.env.roll" "${ROLL_HOME_DIR}/.env"; do
    if [[ -f "${globalConfig}" ]]; then
        loadConfigFromFile "${globalConfig}" "false" "global"
    fi
done
ROLL_IMAGE_REPOSITORY="$(getConfig ROLL_IMAGE_REPOSITORY "ghcr.io/epartment/roll")"

cleanupReferences=()
cleanupListing=()
supersededCount=0
unusedCount=0

while IFS=$'\t' read -r reference name size created; do
    cleanupReferences+=("${reference}")
    printf -v listingLine '  %-10s %-60s %-10s %s' "superseded" "${name}" "${size}" "${created}"
    cleanupListing+=("${listingLine}")
    supersededCount=$((supersededCount + 1))
done < <(listSupersededRollImages)

while IFS=$'\t' read -r reference name size created; do
    cleanupReferences+=("${reference}")
    printf -v listingLine '  %-10s %-60s %-10s %s' "unused" "${name}" "${size}" "${created}"
    cleanupListing+=("${listingLine}")
    unusedCount=$((unusedCount + 1))
done < <(listUnusedRollImages)

if (( ${#cleanupReferences[@]} == 0 )); then
    info "No superseded or unused roll images found."
    exit 0
fi

printf '  %-10s %-60s %-10s %s\n' "KIND" "IMAGE" "SIZE" "CREATED"
printf '%s\n' "${cleanupListing[@]}"
echo ""
info "Sizes include layers images share with each other, so the space freed can be less than their sum."

if [[ ${CLEANUP_DRY_RUN} -eq 1 ]]; then
    info "Dry run: ${supersededCount} superseded and ${unusedCount} unused image(s) would be removed."
    exit 0
fi

removeImages "${cleanupReferences[@]}"

success "Removed ${ROLL_IMAGES_REMOVED} of ${#cleanupReferences[@]} image(s). An environment that needs one of them again downloads it on its next 'roll env up'."

if (( ROLL_IMAGES_GONE > 0 )); then
    info "${ROLL_IMAGES_GONE} image(s) were already gone, removed by another roll run in the meantime."
fi

if (( ${#ROLL_IMAGES_KEPT[@]} > 0 )); then
    warning "Docker kept ${#ROLL_IMAGES_KEPT[@]} image(s), usually because a container still uses them:"
    for kept in "${ROLL_IMAGES_KEPT[@]}"; do
        >&2 printf '  %s\n' "${kept}"
    done
fi
