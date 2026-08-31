#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
    warning "This command is only available for Magento 2 projects" && exit 1
fi

ROLL_ENV_SHELL_CONTAINER=${ROLL_ENV_SHELL_CONTAINER:-php-fpm}
FPM_CONTAINER=$(roll env ps -q "${ROLL_ENV_SHELL_CONTAINER}")
if [[ ! ${FPM_CONTAINER} ]]; then
    fatal "Your project is not running. Please use \`roll start\` to start your project."
fi

## theme discovery is rooted at the project's app/design/frontend, never at $PWD - otherwise
## running the command from any directory but the project root reports no themes at all
THEME_ROOT="${ROLL_ENV_PATH}/app/design/frontend"

INSTALL_THEMES=($(find "${THEME_ROOT}" -maxdepth 3 -name 'package.json' 2>/dev/null \
    | sed -e 's#/package\.json$##' -e "s#^${THEME_ROOT}/##"))
AVAILABLE_THEMES=($(find "${THEME_ROOT}" -name 'Gulpfile.js' 2>/dev/null \
    | sed -e 's#/Gulpfile\.js$##' -e "s#^${THEME_ROOT}/##"))

## boilerplate detection must inspect every discovered theme, not just the first one - grepping
## "${AVAILABLE_THEMES[@]}" without printf'ing each element on its own line yields only element 0
BOILERPLATE_THEME=()
if (( ${#AVAILABLE_THEMES[@]} > 0 )); then
    BOILERPLATE_THEME=($(printf '%s\n' "${AVAILABLE_THEMES[@]}" | grep -e 'Epartment/boilerplate'))
fi

NODE_PACKAGE_MANAGER=${ROLL_NODE_PACKAGE_MANAGER:-yarn}
if (( ${#BOILERPLATE_THEME[@]} > 0 )); then
    YARN_INSTEAD_OF_GULP=1
else
    YARN_INSTEAD_OF_GULP=${ROLL_YARN_INSTEAD_OF_GULP:-0}
fi

function installTheme() {
    THEME_DIR="/var/www/html/app/design/frontend/${SELECTED_THEME}"

    "${ROLL_DIR}/bin/roll" env exec -T -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" "${NODE_PACKAGE_MANAGER}" install
    info "Rebuilding node-sass package..."
    "${ROLL_DIR}/bin/roll" env exec -T -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" npm rebuild node-sass
}

function buildTheme() {
    THEME_DIR="/var/www/html/app/design/frontend/${SELECTED_THEME}"

    if [[ ${YARN_INSTEAD_OF_GULP} == 1 ]]; then
        "${ROLL_DIR}/bin/roll" env exec -T -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" yarn run dev
    else
        "${ROLL_DIR}/bin/roll" env exec -T -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" gulp build
    fi
}

function watchTheme() {
    THEME_DIR="/var/www/html/app/design/frontend/${SELECTED_THEME}"

    if [[ ${YARN_INSTEAD_OF_GULP} == 1 ]]; then
        "${ROLL_DIR}/bin/roll" env exec -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" yarn run watch
    else
        "${ROLL_DIR}/bin/roll" env exec -u www-data --workdir "${THEME_DIR}" "${ROLL_ENV_SHELL_CONTAINER}" gulp watch
    fi
}

function buildAll() {
    local theme_dir=""

    for theme_dir in "${INSTALL_THEMES[@]}"; do
        SELECTED_THEME="${theme_dir}"
        installTheme
    done

    for theme_dir in "${AVAILABLE_THEMES[@]}"; do
        SELECTED_THEME="${theme_dir}"
        buildTheme
    done

    return 0
}

if (( ${#ROLL_PARAMS[@]} == 0 )); then
    ## interactive: nothing to build was named on the command line
    if (( ${#AVAILABLE_THEMES[@]} == 0 )); then
        fatal "No themes with a Gulpfile.js were found under ${THEME_ROOT}."
    fi

    if (( ${#AVAILABLE_THEMES[@]} == 1 )); then
        SELECTED_THEME="${AVAILABLE_THEMES[0]}"
    else
        promptChoose SELECTED_THEME "roll theme <vendor/name> build|watch" \
            "Which theme do you want to build or watch?" "${AVAILABLE_THEMES[@]}"
    fi
elif [[ "${ROLL_PARAMS[0]}" == "all" ]]; then
    SELECTED_THEME="all"
else
    SELECTED_THEME="${ROLL_PARAMS[0]}"
    if ! containsElement "${SELECTED_THEME}" "${AVAILABLE_THEMES[@]}"; then
        fatal "Theme '${SELECTED_THEME}' was not found under ${THEME_ROOT}."
    fi
fi

if [[ "${SELECTED_THEME}" == "all" ]]; then
    buildAll
    exit 0
fi

ACTION="${ROLL_PARAMS[1]:-}"
promptChoose ACTION "roll theme ${SELECTED_THEME} build|watch" \
    "Do you want to build or watch ${SELECTED_THEME}?" "build" "watch"

if [[ "${ACTION}" != "build" && "${ACTION}" != "watch" ]]; then
    fatal "Unknown action '${ACTION}'; expected 'build' or 'watch'."
fi

buildTheme

if [[ "${ACTION}" == "watch" ]]; then
    watchTheme
fi
