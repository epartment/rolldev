#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  roll config --help || exit $? && exit $?
fi

## Sub-command execution
case "${ROLL_PARAMS[0]}" in
    show)
        # Try to load configuration if in a project directory
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
                error "Failed to load configuration from ${ROLL_ENV_PATH}/.env.roll"
                exit 1
            }
        else
            warning "Not in a Roll project directory"
            exit 1
        fi
        
        # Filter configuration if specified
        filter="${ROLL_PARAMS[1]:-}"
        showConfig "$filter"
        ;;
        
    validate)
        config_file="${ROLL_PARAMS[1]:-}"
        
        if [[ -z "$config_file" ]]; then
            if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
                config_file="${ROLL_ENV_PATH}/.env.roll"
            else
                error "No configuration file specified and not in a Roll project directory"
                exit 1
            fi
        fi
        
        if [[ ! -f "$config_file" ]]; then
            error "Configuration file not found: $config_file"
            exit 1
        fi
        
        info "Validating configuration: $config_file"
        
        if validateConfig "$config_file"; then
            success "Configuration is valid"
            
            # Also check for conflicts if we can load the config
            if loadRollConfig "$(dirname "$config_file")" >/dev/null 2>&1; then
                if checkConfigConflicts >/dev/null 2>&1; then
                    success "No configuration conflicts detected"
                else
                    warning "Configuration conflicts detected (see above)"
                    exit 1
                fi
            fi
        else
            error "Configuration validation failed"
            exit 1
        fi
        ;;
        
    conflicts)
        # Check for configuration conflicts
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
                error "Failed to load configuration from ${ROLL_ENV_PATH}/.env.roll"
                exit 1
            }
        else
            error "Not in a Roll project directory"
            exit 1
        fi
        
        info "Checking for configuration conflicts..."
        
        if checkConfigConflicts; then
            success "No configuration conflicts detected"
        else
            error "Configuration conflicts detected (see above)"
            exit 1
        fi
        ;;
        
    schema)
        # Display configuration schema
        initConfigSchema
        
        echo -e "\033[33mRoll Configuration Schema:\033[0m"
        echo ""
        
        # Group configurations by category
        echo -e "\033[36mCore Configuration:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            case "$key" in
                ROLL_ENV_NAME|ROLL_ENV_TYPE|ROLL_ENV_SUBT)
                    printf "  %-30s %s\n" "$key" "$value"
                    ;;
            esac
            i=$((i + 1))
        done
        
        echo ""
        echo -e "\033[36mService Toggles:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            if [[ "$key" =~ ^ROLL_(NGINX|DB|REDIS|DRAGONFLY|VARNISH|ELASTICSEARCH|OPENSEARCH|ELASTICVUE|RABBITMQ|MONGODB|BROWSERSYNC|PUBLISH_PORTS|SELENIUM|TEST_DB|ALLURE|MAGEPACK|INCLUDE_GIT) ]] && [[ ! "$key" =~ _VERSION$ ]]; then
                printf "  %-30s %s\n" "$key" "$value"
            fi
            i=$((i + 1))
        done
        
        echo ""
        echo -e "\033[36mPHP/Node/Composer Configuration:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            if [[ "$key" =~ ^(PHP_|COMPOSER_|NODE_) ]] || [[ "$key" =~ ^XDEBUG ]] \
                || [[ "$key" =~ ^ROLL_(NODE_PACKAGE_MANAGER|YARN_INSTEAD_OF_GULP)$ ]]; then
                printf "  %-30s %s\n" "$key" "$value"
            fi
            i=$((i + 1))
        done
        
        echo ""
        echo -e "\033[36mDatabase Configuration:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            if [[ "$key" =~ ^(DB_|MYSQL_|MARIADB_) ]]; then
                printf "  %-30s %s\n" "$key" "$value"
            fi
            i=$((i + 1))
        done
        
        echo ""
        echo -e "\033[36mService Version Configuration:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            if [[ "$key" =~ (_VERSION|_JAVA_OPTS)$ ]] && [[ ! "$key" =~ ^(PHP_|DB_|MYSQL_|MARIADB_|NODE_|XDEBUG_|COMPOSER_) ]]; then
                printf "  %-30s %s\n" "$key" "$value"
            fi
            i=$((i + 1))
        done
        
        echo ""
        echo -e "\033[36mTraefik/Network Configuration:\033[0m"
        i=0
        while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
            key="${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
            value="${ROLL_CONFIG_SCHEMA_VALUES[$i]}"
            if [[ "$key" =~ ^TRAEFIK_ ]]; then
                printf "  %-30s %s\n" "$key" "$value"
            fi
            i=$((i + 1))
        done
        ;;
        
    set)
        if [[ ${#ROLL_PARAMS[@]} -lt 3 ]]; then
            error "Usage: roll config set <key> <value>"
            exit 1
        fi
        
        key="${ROLL_PARAMS[1]}"
        value="${ROLL_PARAMS[2]}"
        
        # Validate the configuration value
        initConfigSchema
        if ! validateConfigValue "$key" "$value"; then
            error "Invalid value for $key: $value"
            exit 1
        fi
        
        # Find configuration file
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            config_file="${ROLL_ENV_PATH}/.env.roll"
        else
            error "Not in a Roll project directory"
            exit 1
        fi
        
        ## Backs up, then rewrites the key in place, uncomments a commented one, or appends it -
        ## see writeEnvRollValue in utils/config.sh
        writeEnvRollValue "$config_file" "$key" "$value" || exit 1

        success "Configuration updated: ${key}=${value}"
        info "Backup created: ${ROLL_CONFIG_WRITE_BACKUP}"
        ;;
        
    get)
        if [[ ${#ROLL_PARAMS[@]} -lt 2 ]]; then
            error "Usage: roll config get <key> [default]"
            exit 1
        fi
        
        key="${ROLL_PARAMS[1]}"
        default_value="${ROLL_PARAMS[2]:-}"
        
        # Load configuration if in project directory
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
                error "Failed to load configuration"
                exit 1
            }
        fi
        
        value="$(getConfig "$key" "$default_value")"
        echo "$value"
        ;;
        
    check-pins|fix-pins)
        ## check-pins reports; fix-pins writes. Both use the versions the project is running right
        ## now, so neither can change which images it runs. Unpinned versions warn from 0.8.0 and
        ## become an error in 0.9.0.
        ##
        ## No --dry-run flag: `config` is not on bin/roll's ROLL_CMD_ANYARGS list, so any
        ## dash-prefixed argument is rejected before this file is even sourced. check-pins is the
        ## read-only form.
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            config_file="${ROLL_ENV_PATH}/.env.roll"
        else
            error "Not in a Roll project directory"
            exit 1
        fi

        ## loadRollConfig populates ROLL_MISSING_PINS and then fills those variables in with the
        ## legacy defaults, so the list must be read from that load - re-collecting afterwards
        ## would always come back empty.
        loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
            error "Failed to load configuration from ${config_file}"
            exit 1
        }

        if (( ${#ROLL_MISSING_PINS[@]} == 0 )); then
            success "Every enabled service already has its version pinned."
            exit 0
        fi

        if [[ "${ROLL_PARAMS[0]}" == "check-pins" ]]; then
            warning "${#ROLL_MISSING_PINS[@]} enabled service(s) have no version pin in ${config_file}:"
            i=0
            while [[ $i -lt ${#ROLL_MISSING_PINS[@]} ]]; do
                key="${ROLL_MISSING_PINS[$i]}"
                echo "    ${key}=$(getRunningVersion "${key}")"
                i=$((i + 1))
            done
            info "Run \`roll config fix-pins\` to write these into .env.roll."
            exit 1
        fi

        cp "${config_file}" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        printf '\n# Version pins added by `roll config fix-pins`. These are the versions this project\n' >> "${config_file}"
        printf '# was already running; change them deliberately, not by upgrading roll.\n' >> "${config_file}"

        i=0
        while [[ $i -lt ${#ROLL_MISSING_PINS[@]} ]]; do
            key="${ROLL_MISSING_PINS[$i]}"
            value="$(getRunningVersion "${key}")"
            echo "${key}=${value}" >> "${config_file}"
            success "Pinned ${key}=${value}"
            i=$((i + 1))
        done
        success "Wrote ${#ROLL_MISSING_PINS[@]} pin(s) to ${config_file}"
        ;;

    versions)
        ## Read-only companion to `version`: with no argument it reports what this project pins,
        ## which needs no network; with a service it lists that service's published versions on
        ## stdout, one per line, so it can be piped. Everything explanatory goes to stderr via the
        ## messaging helpers, keeping stdout parseable.
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            config_file="${ROLL_ENV_PATH}/.env.roll"
        else
            error "Not in a Roll project directory"
            exit 1
        fi

        loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
            error "Failed to load configuration from ${config_file}"
            exit 1
        }

        service="${ROLL_PARAMS[1]:-}"

        if [[ -z "${service}" ]]; then
            echo -e "\033[33mService versions pinned by ${config_file}:\033[0m"
            echo ""
            showServiceVersions
            echo ""
            info "\`roll config version\` changes one; \`roll config versions <service>\` lists what is available."
            exit 0
        fi

        if ! isImageService "${service}"; then
            error "Unknown service: ${service}"
            echo "Available services: $(imageServiceSlugs | tr '\n' ' ')"
            exit 1
        fi

        version_key="$(versionKeyForService "${service}")"
        current="$(getConfig "${version_key}" "")"

        case "$(imageCatalogField "${service}" source)" in
            phpnode)
                ## Node ships as a suffix on the PHP image's tag, so the list depends on the PHP
                ## version in effect - another PHP version's Node builds are tags this project
                ## cannot pull.
                php_version="$(getConfig PHP_VERSION "")"
                if [[ -z "${php_version}" ]]; then
                    error "NODE_VERSION depends on PHP_VERSION, which this project does not pin."
                    info "Pin it first with \`roll config version php <version>\`."
                    exit 1
                fi
                [[ -n "${current}" ]] && info "${version_key} is currently ${current} (Node builds of PHP ${php_version})"
                availableNodeVersions "${php_version}" || exit 1
                ;;
            registry)
                [[ -n "${current}" ]] && info "${version_key} is currently ${current}"
                availableServiceVersions "${service}" || exit 1
                ;;
            *)
                error "RollDev cannot list versions of $(imageCatalogField "${service}" image)."
                info "It is not published under \${ROLL_IMAGE_REPOSITORY}; set ${version_key} with \`roll config version ${service} <version>\`."
                exit 1
                ;;
        esac
        ;;

    version)
        ## Pick a service, pick one of the versions its image actually has, write it to .env.roll.
        ## The version list comes from the registry the environment pulls from, so it cannot go
        ## stale the way a list maintained in this repository would - see utils/images.sh.
        ##
        ## Positional arguments only: `config` is not on bin/roll's ROLL_CMD_ANYARGS list, so a
        ## dash-prefixed argument never reaches this file. The non-interactive form is
        ## `roll config version <service> <version>`.
        if ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)"; then
            config_file="${ROLL_ENV_PATH}/.env.roll"
        else
            error "Not in a Roll project directory"
            exit 1
        fi

        loadRollConfig "${ROLL_ENV_PATH}" >/dev/null 2>&1 || {
            error "Failed to load configuration from ${config_file}"
            exit 1
        }

        service="${ROLL_PARAMS[1]:-}"

        ## Choosing the service touches no network, so a machine that cannot reach the registry
        ## still gets this far and then fails about the registry rather than about the prompt.
        if [[ -z "${service}" ]]; then
            echo -e "\033[33mService versions pinned by ${config_file}:\033[0m"
            echo ""
            showServiceVersions
            echo ""
            # shellcheck disable=SC2046
            promptChoose service "roll config version <service> <version>" \
                "Which service's version do you want to change?" $(imageServiceSlugs)
        fi

        if ! isImageService "${service}"; then
            error "Unknown service: ${service}"
            echo "Available services: $(imageServiceSlugs | tr '\n' ' ')"
            exit 1
        fi

        version_key="$(versionKeyForService "${service}")"
        version_source="$(imageCatalogField "${service}" source)"
        current="$(getConfig "${version_key}" "")"
        selected="${ROLL_PARAMS[2]:-}"

        if [[ -z "${selected}" ]]; then
            case "${version_source}" in
                phpnode)
                    php_version="$(getConfig PHP_VERSION "")"
                    if [[ -z "${php_version}" ]]; then
                        error "NODE_VERSION depends on PHP_VERSION, which this project does not pin."
                        info "Pin it first with \`roll config version php <version>\`."
                        exit 1
                    fi
                    available="$(availableNodeVersions "${php_version}")" || exit 1
                    ;;
                registry)
                    available="$(availableServiceVersions "${service}")" || exit 1
                    ;;
                *)
                    ## Selenium's tags are not enumerable (see utils/images.sh), so ask for one
                    info "RollDev cannot list versions of $(imageCatalogField "${service}" image); enter one yourself."
                    promptInput selected "roll config version ${service} <version>" \
                        "${version_key} (currently ${current:-unpinned}):" "${current}"
                    available=""
                    ;;
            esac

            if [[ -z "${selected}" ]]; then
                if [[ -z "${available}" ]]; then
                    error "No published versions found for ${service}."
                    exit 1
                fi

                [[ -n "${current}" ]] && info "${version_key} is currently ${current}"
                # shellcheck disable=SC2046
                promptChoose selected "roll config version ${service} <version>" \
                    "Which version of ${service} should ${ROLL_ENV_NAME} run?" $(printf '%s\n' "${available}")
            fi
        fi

        ## The value becomes an image tag, so hold it to what a tag may look like. Checked before
        ## the registry lookup below so a malformed value is rejected on its own terms rather than
        ## first drawing a puzzling "not a published version" warning.
        if [[ ! "${selected}" =~ ^[0-9][0-9a-zA-Z._-]*$ ]]; then
            error "\"${selected}\" is not a valid version for ${version_key}."
            exit 1
        fi

        ## A version given on the command line is not checked the way a picked one is, so say when
        ## it is not a tag we know of - it may be brand new, or a typo, and only the person running
        ## the command can tell which.
        if [[ -n "${ROLL_PARAMS[2]:-}" && "${version_source}" == "registry" ]] \
            && available="$(availableServiceVersions "${service}" 2>/dev/null)" \
            && [[ -n "${available}" ]]
        then
            if ! containsElement "${selected}" ${available}; then
                warning "${selected} is not a published version of $(imageForService "${service}"); \`roll env up\` will fail if that tag does not exist."
            fi
        fi

        ## Switching distribution and switching version are one act here: the image name comes from
        ## DB_DISTRIBUTION and the tag from its version, so picking mysql on a mariadb project has
        ## to move both, or the project would ask for a mysql version of the mariadb image. The two
        ## database slugs also share one version key, so an unchanged version still means a change
        ## when the distribution moves - which is why this is settled before the no-op check.
        db_distribution=""
        switch_distribution=0
        if [[ "${service}" == "mysql" || "${service}" == "mariadb" ]]; then
            db_distribution="$(getConfig DB_DISTRIBUTION mariadb)"
            [[ "${service}" != "${db_distribution}" ]] && switch_distribution=1
        fi

        if [[ "${selected}" == "${current}" && ${switch_distribution} -eq 0 ]]; then
            success "${version_key} is already ${selected}; nothing to change."
            exit 0
        fi

        if [[ ${switch_distribution} -eq 1 ]]; then
            warning "This project runs ${db_distribution}; choosing ${service} switches DB_DISTRIBUTION as well."
            warning "The existing database volume was written by ${db_distribution} and ${service} will not read it."
            warning "Dump the database first, then recreate the volume (\`roll env down -v\`) and import it again."
            if ! promptConfirm "roll config set DB_DISTRIBUTION ${service}" "Switch DB_DISTRIBUTION to ${service}?"; then
                error "Cancelled; nothing was written."
                exit 1
            fi
            writeEnvRollValue "${config_file}" DB_DISTRIBUTION "${service}" || exit 1
            success "DB_DISTRIBUTION=${service}"
        fi

        writeEnvRollValue "${config_file}" "${version_key}" "${selected}" || exit 1

        success "${version_key}=${selected} (was ${current:-unpinned})"
        info "Backup: ${ROLL_CONFIG_WRITE_BACKUP}"

        toggle="$(imageCatalogField "${service}" toggle)"
        if [[ -n "${toggle}" ]] && [[ "$(getConfig "${toggle}" 0)" != "1" ]]; then
            warning "${service} is not enabled in this project; switch it on with \`roll config set ${toggle} 1\`."
            exit 0
        fi

        info "Apply it with \`roll env down && roll env up\`."
        case "${service}" in
            mariadb|mysql|elasticsearch|opensearch|mongodb)
                info "The ${service} data volume was written by the previous version; check that engine's upgrade path before starting it."
                ;;
        esac
        ;;

    *)
        error "Unknown config command: ${ROLL_PARAMS[0]}"
        echo "Available commands: show, validate, conflicts, schema, set, get, version, versions, check-pins, fix-pins"
        exit 1
        ;;
esac 