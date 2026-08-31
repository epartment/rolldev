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
            if [[ "$key" =~ ^(PHP_|COMPOSER_|NODE_) ]] || [[ "$key" =~ ^XDEBUG ]]; then
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
        
        # Create backup
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Update or add the configuration
        if grep -q "^${key}=" "$config_file"; then
            # Update existing key - use different approach for macOS compatibility
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^${key}=.*/${key}=${value}/" "$config_file"
            else
                sed -i "s/^${key}=.*/${key}=${value}/" "$config_file"
            fi
        else
            # Add new key
            echo "${key}=${value}" >> "$config_file"
        fi
        
        success "Configuration updated: ${key}=${value}"
        info "Backup created: ${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
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
                echo "    ${key}=$(getLegacyDefaultVersion "${key}")"
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
            value="$(getLegacyDefaultVersion "${key}")"
            echo "${key}=${value}" >> "${config_file}"
            success "Pinned ${key}=${value}"
            i=$((i + 1))
        done
        success "Wrote ${#ROLL_MISSING_PINS[@]} pin(s) to ${config_file}"
        ;;

    *)
        error "Unknown config command: ${ROLL_PARAMS[0]}"
        echo "Available commands: show, validate, conflicts, schema, set, get, check-pins, fix-pins"
        exit 1
        ;;
esac 