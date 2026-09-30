#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Service catalog and image-tag discovery.
##
## Everything a user can pin a version for is described once, here, as a record per service. The
## catalog answers three questions that were previously answered by hand in three different places:
## which .env.roll key holds a service's version, which toggle decides whether that service runs,
## and which image tag list the version has to come from.
##
## The version lists are NOT maintained here. They are read from the registry the environment
## actually pulls from (${ROLL_IMAGE_REPOSITORY}, ghcr.io/epartment/roll by default) using the
## Docker Registry v2 API, so a version that exists is offered and one that does not is not - no
## curated list in this repository can drift out of date. Responses are cached under
## ${ROLL_HOME_DIR}/tmp/image-tags so a picker that lists several services costs one round trip per
## image per hour rather than one per invocation.

## How long a cached tag list stays fresh, in minutes. ROLL_TAG_CACHE_TTL=0 forces a refetch.
ROLL_TAG_CACHE_TTL="${ROLL_TAG_CACHE_TTL:-60}"

## Service catalog, one colon-delimited record per pinnable service:
##
##   <slug>:<version key>:<toggle key>:<image>:<source>
##
## slug         what the user types and picks from
## version key  the .env.roll key holding the version (may be remapped, see versionKeyForService)
## toggle key   the .env.roll key that switches the service on; empty means "always running"
## image        repository name under ${ROLL_IMAGE_REPOSITORY}; "php-fpm" is resolved per env type
## source       registry  = tags come from the image repository
##              phpnode   = tags come from the PHP image's -nodeNN suffixes
##              manual    = not enumerable, the version is typed in
##
## Selenium is `manual` on purpose: it is the one image not published under
## ${ROLL_IMAGE_REPOSITORY}, and Docker Hub's selenium/standalone-chrome carries thousands of tags
## in four different shapes, so a picker over them would be less usable than typing the version.
ROLL_IMAGE_CATALOG=(
    "php:PHP_VERSION::php-fpm:registry"
    "node:NODE_VERSION::php-fpm:phpnode"
    "mariadb:DB_DISTRIBUTION_VERSION:ROLL_DB:mariadb:registry"
    "mysql:DB_DISTRIBUTION_VERSION:ROLL_DB:mysql:registry"
    "nginx:NGINX_VERSION:ROLL_NGINX:nginx:registry"
    "redis:REDIS_VERSION:ROLL_REDIS:redis:registry"
    "dragonfly:DRAGONFLY_VERSION:ROLL_DRAGONFLY:dragonfly:registry"
    "varnish:VARNISH_VERSION:ROLL_VARNISH:varnish:registry"
    "elasticsearch:ELASTICSEARCH_VERSION:ROLL_ELASTICSEARCH:elasticsearch:registry"
    "opensearch:OPENSEARCH_VERSION:ROLL_OPENSEARCH:opensearch:registry"
    "rabbitmq:RABBITMQ_VERSION:ROLL_RABBITMQ:rabbitmq:registry"
    "mongodb:MONGO_VERSION:ROLL_MONGODB:mongo:registry"
    "magepack:MAGEPACK_VERSION:ROLL_MAGEPACK:magepack:registry"
    "selenium:ROLL_SELENIUM_VERSION:ROLL_SELENIUM:selenium/standalone-chrome:manual"
)

## Every slug in catalog order, one per line.
function imageServiceSlugs() {
    local record=""

    for record in "${ROLL_IMAGE_CATALOG[@]}"; do
        echo "${record%%:*}"
    done

    return 0
}

## imageCatalogField <slug> <key|toggle|image|source>
## Empty output when the slug is unknown, so callers test the slug with isImageService first.
function imageCatalogField() {
    local slug="$1" field="$2"
    local record="" rest=""

    for record in "${ROLL_IMAGE_CATALOG[@]}"; do
        [[ "${record%%:*}" == "${slug}" ]] || continue

        rest="${record#*:}"
        case "${field}" in
            key)    echo "${rest%%:*}" ;;
            toggle) rest="${rest#*:}"; echo "${rest%%:*}" ;;
            image)  rest="${rest#*:}"; rest="${rest#*:}"; echo "${rest%%:*}" ;;
            source) echo "${record##*:}" ;;
            *)      echo "" ;;
        esac
        return 0
    done

    echo ""
    return 0
}

function isImageService() {
    local slug="$1"
    local record=""

    for record in "${ROLL_IMAGE_CATALOG[@]}"; do
        [[ "${record%%:*}" == "${slug}" ]] && return 0
    done

    return 1
}

## The .env.roll key to write for a service, which is not always the catalog's key.
##
## The database version has three spellings: DB_DISTRIBUTION_VERSION is what the image tag is built
## from, while MYSQL_VERSION and MARIADB_VERSION are the older per-distribution names that
## applyEnvTypeDefaults turns into it. A project already using the older spelling must keep using
## it - writing DB_DISTRIBUTION_VERSION alongside it would leave two version lines in .env.roll
## saying different things, with the reader having to know which one wins.
function versionKeyForService() {
    local slug="$1"
    local key=""

    key="$(imageCatalogField "${slug}" key)"

    if [[ "${key}" == "DB_DISTRIBUTION_VERSION" ]]; then
        local legacy=""
        case "${slug}" in
            mysql)   legacy="MYSQL_VERSION" ;;
            mariadb) legacy="MARIADB_VERSION" ;;
        esac

        if [[ -n "${legacy}" ]] && containsElement "${legacy}" "${ROLL_PROJECT_CONFIG_KEYS[@]:-}"; then
            echo "${legacy}"
            return 0
        fi
    fi

    echo "${key}"
    return 0
}

## The image repository a service's tags come from, relative to ${ROLL_IMAGE_REPOSITORY}.
##
## php-fpm is per environment type: postProcessConfig appends -magento1/-magento2/-wordpress to the
## image name for those types, so the tag list has to come from the same variant the environment
## will actually pull. Getting this wrong would offer a PHP version that exists for plain php-fpm
## but was never built for, say, the magento2 variant.
function imageForService() {
    local slug="$1"
    local image=""

    image="$(imageCatalogField "${slug}" image)"

    if [[ "${image}" == "php-fpm" ]]; then
        case "${ROLL_ENV_TYPE:-}" in
            magento1|magento2|wordpress) image="php-fpm-${ROLL_ENV_TYPE}" ;;
        esac
    fi

    echo "${image}"
    return 0
}

## Split ${ROLL_IMAGE_REPOSITORY} into its registry host and namespace path. A repository without a
## host component (a bare "epartment/roll") is a Docker Hub reference, which the v2 API serves from
## registry-1.docker.io under the library/ namespace for single-segment names.
function imageRegistryHost() {
    local repository="${ROLL_IMAGE_REPOSITORY:-ghcr.io/epartment/roll}"
    local first="${repository%%/*}"

    ## A host has a dot, a colon, or is exactly "localhost"; anything else is a Docker Hub namespace
    if [[ "${first}" == *.* || "${first}" == *:* || "${first}" == "localhost" ]]; then
        echo "${first}"
    else
        echo "registry-1.docker.io"
    fi

    return 0
}

function imageRegistryPath() {
    local repository="${ROLL_IMAGE_REPOSITORY:-ghcr.io/epartment/roll}"
    local first="${repository%%/*}"

    if [[ "${first}" == *.* || "${first}" == *:* || "${first}" == "localhost" ]]; then
        echo "${repository#*/}"
    else
        echo "${repository}"
    fi

    return 0
}

## Pull the "tags" array out of a v2 tags/list response without needing jq. The body is a single
## line, so cutting at the key and then at the closing bracket is enough; an empty repository
## answers `"tags":null`, which yields nothing.
function parseRegistryTags() {
    local body="$1"

    case "${body}" in
        *'"tags"'*) ;;
        *) return 0 ;;
    esac

    printf '%s' "${body}" \
        | sed -e 's/.*"tags"[[:space:]]*:[[:space:]]*\[//' -e 's/\].*//' \
        | tr ',' '\n' \
        | tr -d '"' \
        | sed -e 's/[[:space:]]//g' \
        | grep -v '^$' || true

    return 0
}

## fetchRegistryTags <image>
##
## Every tag of ${ROLL_IMAGE_REPOSITORY}/<image>, one per line, newest-first ordering NOT applied.
## Cached for ROLL_TAG_CACHE_TTL minutes. Returns 1 - with nothing on stdout - when the registry
## could not be read, so a caller can fall back to asking for the version instead of pretending the
## image has no tags.
##
## Anonymous pulls are authenticated in two steps: the unauthenticated request answers 401 with a
## WWW-Authenticate header naming a token endpoint, and the token it hands back authorises the
## retry. Reading the realm from the header rather than hardcoding ghcr.io's keeps this working for
## any v2 registry a ROLL_IMAGE_REPOSITORY override might point at.
function fetchRegistryTags() {
    local image="$1"
    local host="" path="" url="" cache_dir="" cache_file="" headers="" body=""
    local challenge="" realm="" service="" scope="" token="" status=0

    host="$(imageRegistryHost)"
    path="$(imageRegistryPath)"

    cache_dir="${ROLL_HOME_DIR:-${HOME}/.roll}/tmp/image-tags"
    cache_file="${cache_dir}/$(printf '%s' "${host}/${path}/${image}" | tr -c '[:alnum:]._-' '_')"

    ## `find -mmin` is the one file-age test that behaves identically on BSD and GNU find
    if [[ -s "${cache_file}" ]] && [[ "${ROLL_TAG_CACHE_TTL}" != "0" ]] \
        && [[ -z "$(find "${cache_file}" -mmin +"${ROLL_TAG_CACHE_TTL}" 2>/dev/null)" ]]
    then
        cat "${cache_file}"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        error "Reading available versions needs \`curl\`, which is not installed."
        return 1
    fi

    url="https://${host}/v2/${path}/${image}/tags/list?n=1000"
    headers="$(mktemp "${TMPDIR:-/tmp}/roll-tags.XXXXXX")"

    body="$(curl -sS -m 15 -D "${headers}" "${url}" 2>/dev/null)" || status=$?

    if [[ ${status} -ne 0 ]]; then
        rm -f "${headers}"
        error "Could not reach ${host} to list versions of ${path}/${image}."
        return 1
    fi

    ## 401 is the normal first answer for an anonymous pull; take the challenge and come back
    challenge="$(grep -i '^www-authenticate:' "${headers}" | head -n1)" || true
    rm -f "${headers}"

    if [[ -n "${challenge}" ]]; then
        realm="$(printf '%s' "${challenge}" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')"
        service="$(printf '%s' "${challenge}" | sed -n 's/.*service="\([^"]*\)".*/\1/p')"
        scope="$(printf '%s' "${challenge}" | sed -n 's/.*scope="\([^"]*\)".*/\1/p')"
        [[ -z "${scope}" ]] && scope="repository:${path}/${image}:pull"

        if [[ -n "${realm}" ]]; then
            token="$(curl -sS -m 15 --get \
                --data-urlencode "service=${service}" \
                --data-urlencode "scope=${scope}" \
                "${realm}" 2>/dev/null \
                | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')" || true
        fi

        if [[ -z "${token}" ]]; then
            error "Could not obtain a pull token for ${path}/${image} from ${host}."
            return 1
        fi

        body="$(curl -sS -m 15 -H "Authorization: Bearer ${token}" "${url}" 2>/dev/null)" || status=$?
        if [[ ${status} -ne 0 ]]; then
            error "Could not reach ${host} to list versions of ${path}/${image}."
            return 1
        fi
    fi

    local tags=""
    tags="$(parseRegistryTags "${body}")"

    if [[ -z "${tags}" ]]; then
        error "${host}/${path}/${image} reported no tags."
        return 1
    fi

    mkdir -p "${cache_dir}" 2>/dev/null || true
    printf '%s\n' "${tags}" > "${cache_file}" 2>/dev/null || true

    printf '%s\n' "${tags}"
    return 0
}

## Newest first, on stdin. Field-wise numeric sort rather than `sort -V`: BSD and GNU sort agree on
## this form, and it puts a non-numeric tag such as `latest` last instead of first.
function sortVersionsDesc() {
    sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr -u
    return 0
}

## The version tags of an image: the build-cache and floating tags dropped, and for php-fpm the
## -nodeNN suffixes stripped, since the suffix is NODE_VERSION's business and not PHP's.
function availableServiceVersions() {
    local slug="$1"
    local image="" tags=""

    image="$(imageForService "${slug}")"
    tags="$(fetchRegistryTags "${image}")" || return 1

    printf '%s\n' "${tags}" \
        | grep -v -- '-buildcache$' \
        | sed -e 's/-node[0-9x]*$//' \
        | grep -E '^[0-9]+(\.[0-9]+)*$' \
        | sortVersionsDesc

    return 0
}

## The Node versions built into a given PHP image tag, newest first, plus 0 for "no Node at all" -
## which is a real choice: NODE_VERSION=0 makes postProcessConfig leave the -nodeNN suffix off the
## image tag entirely.
function availableNodeVersions() {
    local php_version="$1"
    local image="" tags=""

    image="$(imageForService node)"
    tags="$(fetchRegistryTags "${image}")" || return 1

    printf '%s\n' "${tags}" \
        | grep -v -- '-buildcache$' \
        | grep -E "^${php_version}-node[0-9]+$" \
        | sed -e 's/.*-node//' \
        | sort -nr -u

    echo "0"
    return 0
}

## The version this project pins for every catalogued service, and whether that service actually
## runs. Rendered here rather than in the command because it is a view of the catalog, and because
## the version picker shows the same table before asking - a command re-invoking `roll` for it
## would render whatever roll happens to be first on PATH instead of the running one.
##
## Needs loadRollConfig to have run, so the values are the project's own.
function showServiceVersions() {
    local slug="" version_key="" current="" toggle="" status="" distribution=""

    distribution="$(getConfig DB_DISTRIBUTION mariadb)"

    printf "  %-14s %-26s %-12s %s\n" "SERVICE" "KEY" "VERSION" "STATUS"

    for slug in $(imageServiceSlugs); do
        version_key="$(versionKeyForService "${slug}")"
        current="$(getConfig "${version_key}" "")"
        toggle="$(imageCatalogField "${slug}" toggle)"
        status="enabled"

        if [[ -n "${toggle}" ]] && [[ "$(getConfig "${toggle}" 0)" != "1" ]]; then
            status="disabled (${toggle}=0)"
        elif [[ -z "${toggle}" && "${ROLL_ENV_TYPE:-}" == "local" ]]; then
            status="unused (local env type)"
        fi

        ## Both database slugs read the same key, but only the selected distribution runs, so
        ## showing the version against the other one would misreport what the project uses
        if [[ "${slug}" == "mysql" || "${slug}" == "mariadb" ]] && [[ "${slug}" != "${distribution}" ]]; then
            status="not selected (DB_DISTRIBUTION=${distribution})"
            current=""
        fi

        printf "  %-14s %-26s %-12s %s\n" \
            "${slug}" "${version_key}" "${current:-<unpinned>}" "${status}"
    done

    return 0
}

## Image cleanup.
##
## Every `docker compose pull` that finds a newer build of a tag moves the tag onto the new image
## and leaves the old one behind as a dangling image: no tag, the repository name kept through its
## digest, still taking the full size on disk. Nothing in Docker ever removes those, so on a
## developer machine that pulls the nightly-rebuilt roll images they accumulate without limit.
##
## Two classes are told apart here, because only one of them is always garbage:
##
##   superseded  dangling images of a roll repository. Nothing can start a container from them any
##               more, so they are removed without asking, and automatically after a pull.
##   unused      tagged roll images no container uses, e.g. php-fpm:8.1 after a project moved to
##               8.2. Removed by `roll image-cleanup` only, never automatically: `roll env down`
##               and `roll shutdown` remove a project's containers, so the images of every project
##               that is merely down count as unused too, and removing them after every `up`
##               would make each environment download its images again after a shutdown.
##
## Removal never forces. `docker image rm` refuses an image a container still uses, running or
## stopped, and that refusal is what keeps an image a stopped environment needs on disk.

## Repository patterns, as bash globs, of every image roll itself runs: the ${ROLL_IMAGE_REPOSITORY}
## namespace plus the third-party images named literally in roll's compose fragments (traefik,
## mailpit, selenium, ...). Read from the fragments rather than listed here, so a service added
## later is covered without touching this function. An interpolation inside a name becomes `*`, so
## selenium/standalone-chrome${ROLL_SELENIUM_DEBUG:-} matches the plain and the -debug image.
function rollImageRepositoryPatterns() {
    local repository="${ROLL_IMAGE_REPOSITORY:-ghcr.io/epartment/roll}"
    local root=""

    echo "${repository}/*"

    for root in "${ROLL_DIR}/docker" "${ROLL_DIR}/environments" "${ROLL_HOME_DIR:-${HOME}/.roll}/environments"; do
        [[ -d "${root}" ]] || continue

        find "${root}" -type f -name '*.yml' -exec grep -h '^[[:space:]]*image:' {} + 2>/dev/null \
            | sed -e 's/^[[:space:]]*image:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/["'\'']//g' \
            | grep -v '^[$][{]ROLL_IMAGE_REPOSITORY[}]' \
            | sed -e 's/[$][{][^}]*[}]/*/g' -e 's/@.*$//' -e 's/:.*$//' \
            | grep -v '^$' || true
    done | sort -u

    return 0
}

## isRollImageRepository <repository> <pattern>...
function isRollImageRepository() {
    local repository="$1"
    shift
    local pattern=""

    for pattern in "$@"; do
        # shellcheck disable=SC2053  # the pattern is a glob on purpose
        [[ "${repository}" == ${pattern} ]] && return 0
    done

    return 1
}

## Superseded roll images, one "<image id>\t<repository>\t<size>\t<created>" line each. A dangling
## image whose repository is <none> as well carries no trace of where it came from, so it is not
## roll's to remove.
function listSupersededRollImages() {
    local patterns=() line="" id="" repository="" size="" created=""

    while IFS= read -r line; do
        patterns+=("${line}")
    done < <(rollImageRepositoryPatterns)

    while IFS=$'\t' read -r id repository size created; do
        [[ -z "${id}" || "${repository}" == "<none>" ]] && continue
        isRollImageRepository "${repository}" "${patterns[@]}" || continue
        printf '%s\t%s\t%s\t%s\n' "${id}" "${repository}" "${size}" "${created}"
    done < <(docker image ls --filter dangling=true --no-trunc \
        --format '{{.ID}}\t{{.Repository}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)

    return 0
}

## An image reference as `docker image ls` spells it: Docker Hub prefixes dropped and the implicit
## :latest made explicit, so `traefik` and `docker.io/library/traefik:latest` compare equal.
## normalizeImageReference <varname> <reference> - assigns rather than prints, so a loop over every
## container on the host does not fork a subshell per container.
function normalizeImageReference() {
    local var="$1" image_reference="$2"

    image_reference="${image_reference#docker.io/}"
    image_reference="${image_reference#library/}"

    if [[ "${image_reference}" != *@* && "${image_reference##*/}" != *:* ]]; then
        image_reference="${image_reference}:latest"
    fi

    printf -v "${var}" '%s' "${image_reference}"
    return 0
}

## Tagged roll images no container uses, one "<repository:tag>\t<repository:tag>\t<size>\t<created>"
## line each. The reference is the tag rather than the image id: one image can carry several tags,
## and removing it by id is refused while more than one tag points at it.
##
## A container counts against a tag both through the image id it runs and through the tag it was
## created from. The second matters after a pull: the tag has moved on to a newer image that no
## container runs yet, while the environment still names that tag and would pull it straight back
## on its next `up`.
function listUnusedRollImages() {
    local patterns=() containers=() used="" line="" id="" repository="" tag="" size="" created=""
    local image="" config_image="" reference=""

    while IFS= read -r line; do
        patterns+=("${line}")
    done < <(rollImageRepositoryPatterns)

    ## Stopped containers count: `roll env stop` leaves them in place and `env start` reuses them
    while IFS= read -r line; do
        [[ -n "${line}" ]] && containers+=("${line}")
    done < <(docker container ls -aq --no-trunc 2>/dev/null)

    if (( ${#containers[@]} > 0 )); then
        while IFS=$'\t' read -r image config_image; do
            normalizeImageReference reference "${config_image}"
            used="${used}${image}"$'\n'"${reference}"$'\n'
        done < <(docker container inspect --format '{{.Image}}{{"\t"}}{{.Config.Image}}' "${containers[@]}" 2>/dev/null)
    fi

    while IFS=$'\t' read -r id repository tag size created; do
        [[ -z "${id}" || "${tag}" == "<none>" ]] && continue
        isRollImageRepository "${repository}" "${patterns[@]}" || continue
        [[ $'\n'"${used}" == *$'\n'"${id}"$'\n'* ]] && continue
        [[ $'\n'"${used}" == *$'\n'"${repository}:${tag}"$'\n'* ]] && continue
        printf '%s:%s\t%s:%s\t%s\t%s\n' "${repository}" "${tag}" "${repository}" "${tag}" "${size}" "${created}"
    done < <(docker image ls --filter dangling=false --no-trunc \
        --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)

    return 0
}

## removeImages <reference>...
##
## Removes each image without forcing, and leaves the outcome in ROLL_IMAGES_REMOVED (a count),
## ROLL_IMAGES_GONE (a count of images that had disappeared before this run got to them) and
## ROLL_IMAGES_KEPT (one "<reference>: <docker's reason>" line per image Docker refused, typically
## because a container still uses it).
##
## An image that has disappeared is told apart by asking Docker whether it still exists, not by
## parsing the refusal: parallel `env up`s each run the automatic cleanup over the same list, and
## Docker words "already removed" differently depending on the reference form ("No such image",
## "unrecognized image ID"), so reporting those as kept would blame a container that does not exist.
function removeImages() {
    local reference="" output=""

    ROLL_IMAGES_REMOVED=0
    ROLL_IMAGES_GONE=0
    ROLL_IMAGES_KEPT=()

    for reference in "$@"; do
        if output="$(docker image rm "${reference}" 2>&1)"; then
            ROLL_IMAGES_REMOVED=$((ROLL_IMAGES_REMOVED + 1))
        elif ! docker image inspect "${reference}" >/dev/null 2>&1; then
            ROLL_IMAGES_GONE=$((ROLL_IMAGES_GONE + 1))
        else
            ROLL_IMAGES_KEPT+=("${reference}: ${output%%$'\n'*}")
        fi
    done

    return 0
}

## The automatic cleanup after `roll svc pull|up` and `roll env pull|up`: superseded images only,
## silent unless it removed something. `up` is included because a pull cannot remove the image a
## running container still holds; the `up` that recreates that container is the first moment the
## old image is free.
##
## ROLL_IMAGE_AUTO_CLEANUP=0 turns it off, from ~/.roll/.env, a project's .env.roll or the process
## environment. The schema declares the key optional rather than defaulting it, so an exported
## default can never overwrite the value an unattended caller passed in.
function autoCleanupRollImages() {
    local references=() line=""

    [[ "$(getConfig ROLL_IMAGE_AUTO_CLEANUP 1)" == "0" ]] && return 0

    while IFS= read -r line; do
        references+=("${line%%$'\t'*}")
    done < <(listSupersededRollImages)

    (( ${#references[@]} > 0 )) || return 0

    removeImages "${references[@]}"

    if (( ROLL_IMAGES_REMOVED > 0 )); then
        info "Removed ${ROLL_IMAGES_REMOVED} superseded roll image(s). Run 'roll image-cleanup' to also remove images no container uses."
    fi

    return 0
}
