#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
## @description: Convert a Warden project in the current directory to RollDev.
## @category: utility

CURRENT_DIR="$(pwd -P)"

if [[ -f "${CURRENT_DIR}/.env.roll" ]]; then
  info "${CURRENT_DIR}/.env.roll already exists; nothing to convert."
  exit 0
fi

if [[ ! -f "${CURRENT_DIR}/.env" ]]; then
  fatal "No .env file found in ${CURRENT_DIR}; this does not look like a Warden project."
fi

IS_WARDEN=$(grep -e 'WARDEN' "${CURRENT_DIR}/.env") || true
if [[ -z ${IS_WARDEN} ]]; then
  fatal "${CURRENT_DIR}/.env does not reference WARDEN; this does not look like a Warden project."
fi

if command -v warden >/dev/null 2>&1; then
  warden env down 2>/dev/null || true
fi

info "Converting Warden environment variables to RollDev..."

## Rename WARDEN_* variables to ROLL_*. Leave every other value alone - notably
## ELASTICSEARCH_VERSION, which used to be overwritten with a hardcoded, outdated version here.
sed_inplace "s/WARDEN/ROLL/g" "${CURRENT_DIR}/.env"

## NO_STATIC_CACHING is a negative-form key roll never supported - it is in no schema, so it only
## ever produced an unknown-key warning. Its supported equivalent is ROLL_MAGENTO_STATIC_CACHING,
## which is positive-form (1 selects the production nginx template), so the value has to be
## INVERTED rather than renamed. Nothing is written when the legacy key is absent: the schema
## default of 0 already gives the dev template such a project has been running all along.
if grep -q '^[[:space:]]*ROLL_NO_STATIC_CACHING=' "${CURRENT_DIR}/.env"; then
  LEGACY_NO_STATIC_CACHING="$(sed -n 's/^[[:space:]]*ROLL_NO_STATIC_CACHING=//p' "${CURRENT_DIR}/.env" | tail -n 1)"
  LEGACY_NO_STATIC_CACHING="${LEGACY_NO_STATIC_CACHING//[[:space:]]/}"
  if [[ "${LEGACY_NO_STATIC_CACHING}" == "1" ]]; then
    MAGENTO_STATIC_CACHING=0
  else
    MAGENTO_STATIC_CACHING=1
  fi
  sed_inplace "/^[[:space:]]*ROLL_NO_STATIC_CACHING=/d" "${CURRENT_DIR}/.env"
  echo "ROLL_MAGENTO_STATIC_CACHING=${MAGENTO_STATIC_CACHING}" >> "${CURRENT_DIR}/.env"
  info "Translated ROLL_NO_STATIC_CACHING=${LEGACY_NO_STATIC_CACHING} to ROLL_MAGENTO_STATIC_CACHING=${MAGENTO_STATIC_CACHING}."
fi

if [[ -d "${CURRENT_DIR}/.warden" ]]; then
  mv -- "${CURRENT_DIR}/.warden" "${CURRENT_DIR}/.roll"
  if [[ -f "${CURRENT_DIR}/.roll/warden-env.yml" ]]; then
    mv -- "${CURRENT_DIR}/.roll/warden-env.yml" "${CURRENT_DIR}/.roll/roll-env.yml"
    sed_inplace "s/WARDEN/ROLL/g;s/warden/roll/g" "${CURRENT_DIR}/.roll/roll-env.yml"
  fi
fi

if grep -q 'ROLL_' "${CURRENT_DIR}/.env"; then
  mv -- "${CURRENT_DIR}/.env" "${CURRENT_DIR}/.env.roll"
fi

if ! "${ROLL_DIR}/bin/roll" config validate; then
  fatal "Converted configuration failed validation; see errors above. Fix ${CURRENT_DIR}/.env.roll and re-run \"roll config validate\" before starting the environment."
fi

success "Converted ${CURRENT_DIR} from Warden to RollDev."
info "Some service versions may still need a pin - run \"roll config fix-pins\" to write them."

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

DATA_VOLUME="${ROLL_ENV_NAME}_appdata"
if [[ -n "$(docker volume ls -q --filter "name=^${DATA_VOLUME}\$")" ]]; then
  docker volume rm -- "${DATA_VOLUME}"
fi

"${ROLL_DIR}/bin/roll" sign-certificate "*.${TRAEFIK_DOMAIN}"
"${ROLL_DIR}/bin/roll" env up
