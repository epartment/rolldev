#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(pwd -P)"

# Prompt user if there is an extant .env.roll file to ensure they intend to overwrite. Force
# non-interactively with ROLL_ENV_INIT_FORCE=1 (env-init is not on ROLL_CMD_ANYARGS, so a --force
# flag cannot reach this script - see ROLL_CMD_ANYARGS in bin/roll).
if test -f "${ROLL_ENV_PATH}/.env.roll"; then
  if [[ "${ROLL_ENV_INIT_FORCE:-0}" == "1" ]]; then
    info "Overwriting extant .env.roll file"
  elif promptConfirm "ROLL_ENV_INIT_FORCE=1" "A roll env file already exists at ${ROLL_ENV_PATH}/.env.roll; overwrite it?"; then
    info "Overwriting extant .env.roll file"
  else
    exit
  fi
fi

ROLL_ENV_NAME="${ROLL_PARAMS[0]:-}"

# If roll environment name was not provided, prompt user for it
promptInput ROLL_ENV_NAME "roll env-init <name> <type>" "An environment name was not provided; please enter one:"

# The env name becomes the Docker Compose project name, which rejects anything but lowercase
# alphanumerics, hyphens, and underscores, starting with a letter or number. Catch it here instead
# of letting it fail later with a Docker error that names neither RollDev nor .env.roll.
while [[ ! "${ROLL_ENV_NAME}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; do
  if ! isInteractive; then
    fatal "Environment name \"${ROLL_ENV_NAME}\" is invalid: it becomes the Docker Compose project name, which must match ^[a-z0-9][a-z0-9_-]*\$ (lowercase alphanumeric characters, hyphens, and underscores, starting with a letter or number)."
  fi
  ROLL_ENV_NAME=""
  promptInput ROLL_ENV_NAME "roll env-init <name> <type>" "Invalid environment name; it must match ^[a-z0-9][a-z0-9_-]*\$ (lowercase alphanumeric characters, hyphens, and underscores, starting with a letter or number):"
done

ROLL_ENV_TYPE="${ROLL_PARAMS[1]:-}"

# If roll environment type was not provided, prompt user to choose one
if [[ -z "${ROLL_ENV_TYPE}" ]]; then
  ROLL_ENV_TYPES=($(fetchValidEnvTypes))
  promptChoose ROLL_ENV_TYPE "roll env-init <name> <type>" "An environment type was not provided; please choose one:" "${ROLL_ENV_TYPES[@]}"
fi

# Verify the auto-select and/or type path resolves correctly before setting it
assertValidEnvType || exit $?

# Write the .env.roll file to current working directory
cat > "${ROLL_ENV_PATH}/.env.roll" <<EOF
ROLL_ENV_NAME=${ROLL_ENV_NAME}
ROLL_ENV_TYPE=${ROLL_ENV_TYPE}
ROLL_WEB_ROOT=/

TRAEFIK_DOMAIN=${ROLL_ENV_NAME}.test
TRAEFIK_SUBDOMAIN=app
EOF

ENV_INIT_FILE=$(fetchEnvInitFile)
if [[ -n "${ENV_INIT_FILE}" ]]; then
  export ROLL_ENV_NAME
  export GENERATED_APP_KEY="base64:$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64)"
  envsubst '$ROLL_ENV_NAME:$GENERATED_APP_KEY' < "${ENV_INIT_FILE}" >> "${ROLL_ENV_PATH}/.env.roll"
fi