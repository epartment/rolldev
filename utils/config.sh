#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Configuration Management System
## Compatible with Bash 3.2+ (macOS default)
## Cross-platform: Linux, macOS, WSL

# Configuration cache using simple arrays instead of associative arrays for Bash 3.2 compatibility
ROLL_CONFIG_CACHE_KEYS=()
ROLL_CONFIG_CACHE_VALUES=()
ROLL_CONFIG_LOADED_FILES=()

# Configuration schema using indexed arrays
ROLL_CONFIG_SCHEMA_KEYS=()
ROLL_CONFIG_SCHEMA_VALUES=()

# Which config file each key came from. Global config (~/.roll/.env{,.roll}) is loaded into the same
# cache as the project's .env.roll, so the resolved value alone cannot answer "did THIS project pin
# this?" - the version-pin checks below need the origin, not the value.
ROLL_GLOBAL_CONFIG_KEYS=()
ROLL_GLOBAL_CONFIG_VALUES=()
ROLL_PROJECT_CONFIG_KEYS=()

## Helper function to find index of key in array
function findConfigIndex() {
    local key="$1"
    local i=0
    for cached_key in "${ROLL_CONFIG_CACHE_KEYS[@]}"; do
        if [[ "$cached_key" == "$key" ]]; then
            echo $i
            return 0
        fi
        i=$((i + 1))
    done
    echo -1
}

## Helper function to find schema index
function findSchemaIndex() {
    local key="$1"
    local i=0
    for schema_key in "${ROLL_CONFIG_SCHEMA_KEYS[@]}"; do
        if [[ "$schema_key" == "$key" ]]; then
            echo $i
            return 0
        fi
        i=$((i + 1))
    done
    echo -1
}

## Helper function to check if file is loaded
function isFileLoaded() {
    local file="$1"
    local loaded_file
    for loaded_file in "${ROLL_CONFIG_LOADED_FILES[@]}"; do
        if [[ "$loaded_file" == "$file" ]]; then
            return 0
        fi
    done
    return 1
}

# Initialize configuration schema
function initConfigSchema() {
    # Skip if already initialized
    if [[ ${#ROLL_CONFIG_SCHEMA_KEYS[@]} -gt 0 ]]; then
        return 0
    fi
    
    # Core Roll configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_NAME); ROLL_CONFIG_SCHEMA_VALUES+=("string:required")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_TYPE); ROLL_CONFIG_SCHEMA_VALUES+=("string:required")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SUBT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Service toggles (boolean with defaults)
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_NGINX); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_DB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_REDIS); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_DRAGONFLY); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_VARNISH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ELASTICSEARCH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_OPENSEARCH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ELASTICVUE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_REDISINSIGHT); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_RABBITMQ); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MONGODB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_BROWSERSYNC); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_PUBLISH_PORTS); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM_DEBUG); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_TEST_DB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ALLURE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MAGEPACK); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_INCLUDE_GIT); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    
    # Traefik configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_DOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_SUBDOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_LISTEN); ROLL_CONFIG_SCHEMA_VALUES+=("string:127.0.0.1")
    
    # PHP configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_XDEBUG_3); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_MEMORY_LIMIT); ROLL_CONFIG_SCHEMA_VALUES+=("string:2G")
    
    # Composer configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(COMPOSER_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Database configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(DB_DISTRIBUTION); ROLL_CONFIG_SCHEMA_VALUES+=("string:mariadb")
    ROLL_CONFIG_SCHEMA_KEYS+=(DB_DISTRIBUTION_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(MYSQL_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(MARIADB_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Service version configurations
    ROLL_CONFIG_SCHEMA_KEYS+=(ELASTICSEARCH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ELASTICSEARCH_JAVA_OPTS); ROLL_CONFIG_SCHEMA_VALUES+=("string:-Xms64m -Xmx512m")
    ROLL_CONFIG_SCHEMA_KEYS+=(RABBITMQ_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(REDIS_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(DRAGONFLY_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(VARNISH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(OPENSEARCH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(OPENSEARCH_JAVA_OPTS); ROLL_CONFIG_SCHEMA_VALUES+=("string:-Xms64m -Xmx512m")
    ROLL_CONFIG_SCHEMA_KEYS+=(MONGO_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(MAGEPACK_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Node configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(NODE_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    # Both are read by `roll theme`. Optional rather than defaulted on purpose: an unset
    # ROLL_YARN_INSTEAD_OF_GULP means "decide per theme", which a 0/1 default would destroy.
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_NODE_PACKAGE_MANAGER); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_YARN_INSTEAD_OF_GULP); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Nginx configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_TEMPLATE); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_PUBLIC); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Magento specific
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ADMIN_AUTOLOGIN); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MAGENTO_STATIC_CACHING); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    
    # Environment paths and directories
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_WEB_ROOT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SYNC_IGNORE); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_CHOWN_DIR_LIST); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Extensions and customizations
    ROLL_CONFIG_SCHEMA_KEYS+=(ADD_PHP_EXT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # New Relic configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_NEWRELIC); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(NEWRELIC_LICENSE_KEY); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(NEWRELIC_APP_NAME); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Container configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_CONTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("string:php-fpm")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_COMMAND); ROLL_CONFIG_SCHEMA_VALUES+=("string:bash")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_DEBUG_CONTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("string:php-debug")
    
    # Global service configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_STARTPAGE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_PORTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_DOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # XDebug configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(XDEBUG_CONNECT_BACK_HOST); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(XDEBUG_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:debug")
    
    # System configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_RESTART_POLICY); ROLL_CONFIG_SCHEMA_VALUES+=("string:always")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_IMAGE_REPOSITORY); ROLL_CONFIG_SCHEMA_VALUES+=("string:ghcr.io/epartment/roll")
}

## Get schema for a key
function getSchema() {
    local key="$1"
    local index=$(findSchemaIndex "$key")
    if [[ $index -ge 0 ]]; then
        echo "${ROLL_CONFIG_SCHEMA_VALUES[$index]}"
    fi
}

## Validate configuration value against schema
function validateConfigValue() {
    local key="$1"
    local value="$2"
    local schema="$(getSchema "$key")"
    
    if [[ -z "$schema" ]]; then
        # Unknown configuration key - allow but warn
        warning "Unknown configuration key: $key"
        return 0
    fi
    
    local type="${schema%%:*}"
    local constraint="${schema##*:}"
    
    case "$type" in
        boolean)
            if [[ "$value" != "0" && "$value" != "1" ]]; then
                error "Configuration $key must be 0 or 1, got: $value"
                return 1
            fi
            ;;
        string)
            if [[ "$constraint" == "required" && -z "$value" ]]; then
                error "Configuration $key is required but empty"
                return 1
            fi
            if [[ "$key" == "ROLL_ENV_NAME" && -n "$value" && ! "$value" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
                fatal "ROLL_ENV_NAME=\"$value\" is invalid: it becomes the Docker Compose project name, which must match ^[a-z0-9][a-z0-9_-]*\$ (lowercase alphanumeric characters, hyphens, and underscores, starting with a letter or number). Note that the env name also prefixes every named volume, so renaming an existing environment orphans its old volumes and it comes up on an empty database."
            fi
            ;;
        integer)
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                error "Configuration $key must be an integer, got: $value"
                return 1
            fi
            ;;
    esac
    
    return 0
}

## Set default value for configuration if not set
function setConfigDefault() {
    local key="$1"
    local schema="$(getSchema "$key")"
    
    if [[ -z "$schema" ]]; then
        return 0
    fi
    
    local constraint="${schema##*:}"
    
    # Skip if already set or no default available
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 || "$constraint" == "required" || "$constraint" == "optional" ]]; then
        return 0
    fi
    
    # Set default value
    ROLL_CONFIG_CACHE_KEYS+=("$key")
    ROLL_CONFIG_CACHE_VALUES+=("$constraint")
    export "$key"="$constraint"
}

## Load configuration from file with validation
function loadConfigFromFile() {
    local config_file="$1"
    local validate_only="${2:-false}"
    local source_label="${3:-}"
    
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if already loaded
    if isFileLoaded "$config_file" && [[ "$validate_only" == "false" ]]; then
        return 0
    fi
    
    local line_num=0
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove Windows line endings
        line="${line%$'\r'}"
        
        # Parse key=value pairs
        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi
            
            # Validate configuration
            if ! validateConfigValue "$key" "$value"; then
                error "Invalid configuration at $config_file:$line_num"
                errors=$((errors + 1))
                continue
            fi
            
            # Store in cache and export if not validation-only
            if [[ "$validate_only" == "false" ]]; then
                local index=$(findConfigIndex "$key")
                if [[ $index -ge 0 ]]; then
                    # Update existing
                    ROLL_CONFIG_CACHE_VALUES[$index]="$value"
                else
                    # Add new
                    ROLL_CONFIG_CACHE_KEYS+=("$key")
                    ROLL_CONFIG_CACHE_VALUES+=("$value")
                fi
                export "$key"="$value"

                case "$source_label" in
                    global)
                        ROLL_GLOBAL_CONFIG_KEYS+=("$key")
                        ROLL_GLOBAL_CONFIG_VALUES+=("$value")
                        ;;
                    project)
                        ROLL_PROJECT_CONFIG_KEYS+=("$key")
                        ;;
                esac
            fi
            
        elif [[ "$line" =~ ^[[:space:]]*[^=]+$ ]]; then
            warning "Invalid configuration line at $config_file:$line_num: $line"
        fi
        
    done < "$config_file"
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    
    # Mark as loaded
    if [[ "$validate_only" == "false" ]]; then
        ROLL_CONFIG_LOADED_FILES+=("$config_file")
    fi
    
    return 0
}

## Load Roll environment configuration
function loadRollConfig() {
    local config_path="$1"
    
    if [[ -z "$config_path" ]]; then
        config_path="$(locateEnvPath 2>/dev/null)" || {
            error "Could not locate environment configuration"
            return 1
        }
    fi
    
    local config_file="$config_path/.env.roll"
    
    # Initialize schema if not done
    initConfigSchema
    
    ROLL_GLOBAL_CONFIG_KEYS=()
    ROLL_GLOBAL_CONFIG_VALUES=()
    ROLL_PROJECT_CONFIG_KEYS=()
    
    # Load global configuration first from ROLL_HOME_DIR
    local global_config_loaded=0
    
    # Check for new-style global config file
    if [[ -f "${ROLL_HOME_DIR}/.env.roll" ]]; then
        if loadConfigFromFile "${ROLL_HOME_DIR}/.env.roll" "false" "global"; then
            global_config_loaded=1
        else
            warning "Failed to load global configuration from ${ROLL_HOME_DIR}/.env.roll"
        fi
    fi
    
    # Check for legacy global config file
    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        if loadConfigFromFile "${ROLL_HOME_DIR}/.env" "false" "global"; then
            global_config_loaded=1
        else
            warning "Failed to load global configuration from ${ROLL_HOME_DIR}/.env"
        fi
    fi
    
    # Load project-specific configuration (this will override global settings)
    if ! loadConfigFromFile "$config_file" "false" "project"; then
        return 1
    fi
    
    # Set OS-specific defaults
    case "${OSTYPE:-undefined}" in
        darwin*)
            setConfigValue "ROLL_ENV_SUBT" "darwin"
            ;;
        linux*)
            setConfigValue "ROLL_ENV_SUBT" "linux"
            
            # Check for WSL
            if grep -sqi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
                setConfigValue "ROLL_ENV_SUBT" "wsl"
            fi
            ;;
        *)
            error "Unsupported OSTYPE '${OSTYPE:-undefined}'"
            return 1
            ;;
    esac
    
    # Set system-specific exports
    export USER_ID="$(id -u)"
    export GROUP_ID="$(id -g)"
    export OSTYPE="${OSTYPE}"
    
    # Validate environment type before anything derives from it
    if ! assertValidEnvType; then
        return 1
    fi
    
    # Environment-type defaults first: they must see the variables still unset, so they can fill in
    # what this type needs without overriding what the project explicitly configured.
    applyEnvTypeDefaults
    
    # Schema literals fill whatever nothing else has set by now
    local i=0
    while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
        setConfigDefault "${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
        i=$((i + 1))
    done
    
    # Warn about unpinned versions of enabled services and fall back to the recommended value
    applyVersionPinFallbacks
    
    # Derived values last, once every input has its final value
    postProcessConfig
    
    return 0
}

## Set configuration value
function setConfigValue() {
    local key="$1"
    local value="$2"
    
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 ]]; then
        # Update existing
        ROLL_CONFIG_CACHE_VALUES[$index]="$value"
    else
        # Add new
        ROLL_CONFIG_CACHE_KEYS+=("$key")
        ROLL_CONFIG_CACHE_VALUES+=("$value")
    fi
    export "$key"="$value"
}

## The backup path written by the last writeEnvRollValue call, so callers can name it accurately -
## recomputing a timestamp afterwards can land a second later and report a file that does not exist.
ROLL_CONFIG_WRITE_BACKUP=""

## writeEnvRollValue <config file> <key> <value>
##
## Persist KEY=value in a .env.roll, after taking a timestamped backup.
##
## Three cases, in this order of preference:
##   1. an active `KEY=` line is rewritten in place, so the value keeps its position in the file and
##      whatever comment sits above it;
##   2. otherwise a commented `#KEY=` line is replaced, because the environment type templates ship
##      keys that way (`#OPENSEARCH_VERSION=2.19` in magento2's init.env) and appending a second
##      line would leave the file carrying two answers for one key;
##   3. otherwise the line is appended.
## Any further active line for the same key is dropped, since it would override the one just
## written - loadConfigFromFile takes the last occurrence.
##
## Done with a read/write loop rather than `sed -i`: the value goes through no pattern expansion, so
## one containing `/` or `&` cannot corrupt the file, and there is no BSD/GNU `-i` difference to
## work around.
function writeEnvRollValue() {
    local config_file="$1" key="$2" value="$3"
    local line="" tmp_file="" target=-1 i=0
    local lines=()

    if [[ ! -f "${config_file}" ]]; then
        error "Configuration file not found: ${config_file}"
        return 1
    fi

    ## The key is interpolated into the line-matching regex below, so anything that is not a plain
    ## variable name would match lines it has no business matching
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        error "\"${key}\" is not a valid configuration key name."
        return 1
    fi

    ## One backup per roll invocation, not per write. A command that writes twice - the database
    ## distribution and then its version - would otherwise overwrite the pristine backup with the
    ## half-changed file, since both writes land in the same second and so produce the same name.
    ## The variable is process-local, so a value naming a backup of THIS file means the backup for
    ## this invocation has already been taken.
    if [[ "${ROLL_CONFIG_WRITE_BACKUP}" != "${config_file}.backup."* ]] \
        || [[ ! -f "${ROLL_CONFIG_WRITE_BACKUP}" ]]
    then
        ROLL_CONFIG_WRITE_BACKUP="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        if ! cp -- "${config_file}" "${ROLL_CONFIG_WRITE_BACKUP}"; then
            error "Could not write a backup to ${ROLL_CONFIG_WRITE_BACKUP}"
            return 1
        fi
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        lines[${#lines[@]}]="${line}"
    done < "${config_file}"

    while [[ ${i} -lt ${#lines[@]} ]]; do
        if [[ "${lines[$i]}" =~ ^[[:space:]]*${key}= ]]; then
            target=${i}
            break
        fi
        i=$((i + 1))
    done

    if [[ ${target} -lt 0 ]]; then
        i=0
        while [[ ${i} -lt ${#lines[@]} ]]; do
            if [[ "${lines[$i]}" =~ ^[[:space:]]*#[[:space:]]*${key}= ]]; then
                target=${i}
                break
            fi
            i=$((i + 1))
        done
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/roll-env-roll.XXXXXX")"

    ## One redirect around the whole loop rather than one append per line. The info below still
    ## reaches the terminal because the messaging helpers write to stderr.
    {
        i=0
        while [[ ${i} -lt ${#lines[@]} ]]; do
            if [[ ${i} -eq ${target} ]]; then
                printf '%s=%s\n' "${key}" "${value}"
            elif [[ "${lines[$i]}" =~ ^[[:space:]]*${key}= ]]; then
                info "Dropped a later duplicate ${key} line, which would have overridden this one"
            else
                printf '%s\n' "${lines[$i]}"
            fi
            i=$((i + 1))
        done

        if [[ ${target} -lt 0 ]]; then
            printf '%s=%s\n' "${key}" "${value}"
        fi
    } > "${tmp_file}"

    ## cp rather than mv: the destination keeps its inode, owner and permissions
    if ! cp -- "${tmp_file}" "${config_file}"; then
        error "Could not write ${config_file}; its previous content is in ${ROLL_CONFIG_WRITE_BACKUP}"
        rm -f -- "${tmp_file}"
        return 1
    fi

    rm -f -- "${tmp_file}"
    return 0
}

## Apply an environment-type default. Unlike setConfigDefault, which fills in the schema literal,
## this expresses "what this environment type needs unless the project said otherwise", so it must
## run BEFORE the schema loop and must never override a value the user actually wrote in
## .env.roll. A key already in the cache came from a config file, so it is left alone.
function setConfigDerived() {
    local key="$1"
    local value="$2"

    if [[ $(findConfigIndex "$key") -ge 0 ]]; then
        return 0
    fi

    setConfigValue "$key" "$value"
}

## Environment-type service defaults. These used to live at the bottom of postProcessConfig, where
## they could never take effect: the schema loop had already set every toggle to its literal, so
## the ${VAR:-1} fallbacks only ever saw a value that was present but zero. Running them here, on
## the still-unset variables, is what makes a magento2 project bring up Varnish, a search engine
## and RabbitMQ without having to spell out the toggles.
function applyEnvTypeDefaults() {
    if [[ "${ROLL_ENV_TYPE}" != "local" ]]; then
        setConfigDerived ROLL_NGINX 1
        setConfigDerived ROLL_DB 1
        setConfigDerived ROLL_REDIS 1
    fi

    if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
        setConfigDerived ROLL_VARNISH 1
        setConfigDerived ROLL_ELASTICSEARCH 1
        setConfigDerived ROLL_RABBITMQ 1
    fi

    ## DB_DISTRIBUTION_VERSION is the value the image tag is built from; MYSQL_VERSION and
    ## MARIADB_VERSION are the older per-distribution spellings. Derive from whichever matches the
    ## selected distribution, and only when that one was actually provided.
    if [[ $(findConfigIndex DB_DISTRIBUTION_VERSION) -lt 0 ]]; then
        if [[ "${DB_DISTRIBUTION}" == "mysql" ]]; then
            [[ -n "${MYSQL_VERSION}" ]] && setConfigDerived DB_DISTRIBUTION_VERSION "${MYSQL_VERSION}"
        else
            [[ -n "${MARIADB_VERSION}" ]] && setConfigDerived DB_DISTRIBUTION_VERSION "${MARIADB_VERSION}"
        fi
    fi

    return 0
}

## The version a project is currently running for an unpinned key: the literal that used to be
## this key's schema default. It is deliberately NOT the environment type's init.env value - a
## project that never pinned the key has been running the schema default all along, so that is what
## must be written into .env.roll. Recommending init.env here would jump, for example, an existing
## magento2 project from Elasticsearch 7.17 to 8.11 on upgrade, which is precisely the silent
## version change this whole mechanism exists to prevent. New projects get init.env copied by
## env-init, so they never reach this path.
function getLegacyDefaultVersion() {
    local key="$1"

    case "$key" in
        PHP_VERSION) echo "8.1" ;;
        DB_DISTRIBUTION_VERSION) echo "10.4" ;;
        MYSQL_VERSION) echo "8.0" ;;
        MARIADB_VERSION) echo "10.4" ;;
        ELASTICSEARCH_VERSION) echo "7.17" ;;
        RABBITMQ_VERSION) echo "3.11" ;;
        REDIS_VERSION) echo "7.0" ;;
        DRAGONFLY_VERSION) echo "latest" ;;
        VARNISH_VERSION) echo "7.0" ;;
        OPENSEARCH_VERSION) echo "2.5" ;;
        # the mongodb fragment interpolated MONGODB_VERSION, a key the schema never defined, so
        # its own ":-7" literal is what actually ran - not the schema's unused 6.0
        MONGO_VERSION) echo "7" ;;
        NGINX_VERSION) echo "1.27" ;;
        MAGEPACK_VERSION) echo "2.3" ;;
        ROLL_SELENIUM_VERSION) echo "3.141.59" ;;
        NODE_VERSION) echo "18" ;;
        *) echo "" ;;
    esac
}

## The older per-distribution spelling that applyEnvTypeDefaults turns into DB_DISTRIBUTION_VERSION.
function dbDistributionVersionKey() {
    if [[ "${DB_DISTRIBUTION}" == "mysql" ]]; then
        echo "MYSQL_VERSION"
    else
        echo "MARIADB_VERSION"
    fi
}

## Look up a key's value in the global config files, if it was set there at all.
function getGlobalConfigValue() {
    local key="$1"
    local i=0

    while [[ $i -lt ${#ROLL_GLOBAL_CONFIG_KEYS[@]} ]]; do
        if [[ "${ROLL_GLOBAL_CONFIG_KEYS[$i]}" == "${key}" ]]; then
            echo "${ROLL_GLOBAL_CONFIG_VALUES[$i]}"
            return 0
        fi
        i=$((i + 1))
    done

    echo ""
    return 0
}

## The version an unpinned key is running RIGHT NOW, which is what has to be written into
## .env.roll. A value inherited from global config wins over the legacy literal: pinning the
## literal instead would change the image a project running on a global override already uses.
## DB_DISTRIBUTION_VERSION additionally accepts the older per-distribution spellings, because
## applyEnvTypeDefaults derives it from those and that has not happened yet when pins are collected.
function getRunningVersion() {
    local key="$1"
    local inherited=""

    inherited="$(getGlobalConfigValue "${key}")"

    if [[ -z "${inherited}" && "${key}" == "DB_DISTRIBUTION_VERSION" ]]; then
        inherited="$(getGlobalConfigValue "$(dbDistributionVersionKey)")"
    fi

    if [[ -n "${inherited}" ]]; then
        echo "${inherited}"
        return 0
    fi

    getLegacyDefaultVersion "${key}"
}

## Whether the project's own config file pins this key. DB_DISTRIBUTION_VERSION also counts as
## pinned when the project uses one of the older per-distribution spellings, which
## applyEnvTypeDefaults turns into it.
function isVersionPinned() {
    local key="$1"

    if containsElement "${key}" "${ROLL_PROJECT_CONFIG_KEYS[@]}"; then
        return 0
    fi

    if [[ "${key}" == "DB_DISTRIBUTION_VERSION" ]] && containsElement "$(dbDistributionVersionKey)" "${ROLL_PROJECT_CONFIG_KEYS[@]}"; then
        return 0
    fi

    return 1
}

## Every enabled service should have its version pinned in .env.roll. Previously an omitted pin
## silently resolved to a schema literal, so a project could change PHP or database version just by
## upgrading roll.
##
## In 0.8.0 this warns and falls back to the recommended value, so existing projects keep running
## the images they already ran. In 0.9.0 the fallback goes away and a missing pin becomes fatal.
## `roll config fix-pins` writes the recommended lines into .env.roll.
function collectMissingVersionPins() {
    ROLL_MISSING_PINS=()

    ## A pin is judged on the project's own .env.roll, never on the resolved value: global config is
    ## loaded into the same cache first, so a version in ~/.roll/.env would report as pinned while
    ## the project file stays empty and a teammate without that global resolves a different image.
    ## env.cmd never appends the php-fpm partial for the local type, so it needs no PHP or Node
    if [[ "${ROLL_ENV_TYPE}" != "local" ]]; then
        isVersionPinned PHP_VERSION || ROLL_MISSING_PINS+=(PHP_VERSION)
        isVersionPinned NODE_VERSION || ROLL_MISSING_PINS+=(NODE_VERSION)
    fi

    ## toggle:version pairs; the version is required only when its service is switched on
    local requirements=(
        "ROLL_NGINX:NGINX_VERSION"
        "ROLL_DB:DB_DISTRIBUTION_VERSION"
        "ROLL_REDIS:REDIS_VERSION"
        "ROLL_DRAGONFLY:DRAGONFLY_VERSION"
        "ROLL_VARNISH:VARNISH_VERSION"
        "ROLL_ELASTICSEARCH:ELASTICSEARCH_VERSION"
        "ROLL_OPENSEARCH:OPENSEARCH_VERSION"
        "ROLL_RABBITMQ:RABBITMQ_VERSION"
        "ROLL_MONGODB:MONGO_VERSION"
        "ROLL_MAGEPACK:MAGEPACK_VERSION"
        "ROLL_SELENIUM:ROLL_SELENIUM_VERSION"
    )

    local i=0
    local toggle="" version_key="" toggle_value=""
    while [[ $i -lt ${#requirements[@]} ]]; do
        toggle="${requirements[$i]%%:*}"
        version_key="${requirements[$i]##*:}"
        eval "toggle_value=\${${toggle}:-0}"

        if [[ "${toggle_value}" == "1" ]] && ! isVersionPinned "${version_key}"; then
            ROLL_MISSING_PINS+=("${version_key}")
        fi
        i=$((i + 1))
    done

    return 0
}

## Warn about unpinned versions and fall back to the recommended value so the environment still
## comes up exactly as it did before. Becomes a hard error in 0.9.0.
function applyVersionPinFallbacks() {
    collectMissingVersionPins

    if (( ${#ROLL_MISSING_PINS[@]} == 0 )); then
        return 0
    fi

    local i=0
    local key="" value=""
    warning "This ${ROLL_ENV_TYPE} environment enables services whose versions are not pinned."
    warning "Roll is falling back to a built-in version, which means upgrading roll can silently"
    warning "change which image this project runs. From 0.9.0 this will be an error."
    warning "These are the versions the project is running right now - run \`roll config fix-pins\`"
    warning "to write them into .env.roll, or add them by hand:"
    >&2 echo ""
    while [[ $i -lt ${#ROLL_MISSING_PINS[@]} ]]; do
        key="${ROLL_MISSING_PINS[$i]}"
        value="$(getRunningVersion "${key}")"
        >&2 echo "    ${key}=${value}"
        setConfigValue "${key}" "${value}"
        i=$((i + 1))
    done
    >&2 echo ""

    return 0
}

## Post-process configuration after loading
function postProcessConfig() {
    # Set PHP variant based on environment type
    if [[ "${ROLL_ENV_TYPE}" =~ ^magento ]] || [[ "${ROLL_ENV_TYPE}" =~ ^wordpress ]]; then
        export ROLL_SVC_PHP_VARIANT="-${ROLL_ENV_TYPE}"
    fi
    
    # Set Node.js variant
    if [[ "${NODE_VERSION}" != "0" ]]; then
        export ROLL_SVC_PHP_NODE="-node${NODE_VERSION}"
    fi
    
    # XDebug version configuration
    if [[ "${PHP_XDEBUG_3}" == "1" ]]; then
        export XDEBUG_VERSION="xdebug3"
    else
        export XDEBUG_VERSION="debug"
    fi
    
    # WSL XDebug host configuration
    if [[ "${ROLL_ENV_SUBT}" == "wsl" && -z "${XDEBUG_CONNECT_BACK_HOST}" ]]; then
        export XDEBUG_CONNECT_BACK_HOST="host.docker.internal"
    fi
    
    # Linux SSH auth sock path
    if [[ "${ROLL_ENV_SUBT}" == "linux" && "$(id -u)" == "1000" ]]; then
        export SSH_AUTH_SOCK_PATH_ENV="/run/host-services/ssh-auth.sock"
    fi
    
    # Bash history and SSH directories. Always exported, even when empty: the compose fragments
    # interpolate it unconditionally, and an unset variable makes docker compose warn.
    if [[ "${ROLL_ENV_TYPE}" != "local" ]]; then
        export CHOWN_DIR_LIST="/bash_history /home/www-data/.ssh ${ROLL_CHOWN_DIR_LIST:-}"
    else
        export CHOWN_DIR_LIST=""
    fi
    
    # Magento 1 specific configuration
    if [[ "${ROLL_ENV_TYPE}" == "magento1" ]]; then
        if [[ -f "${ROLL_ENV_PATH}/.modman/.basedir" ]]; then
            export NGINX_PUBLIC="/$(cat "${ROLL_ENV_PATH}/.modman/.basedir")"
        fi
        
        if [[ "${ROLL_MAGENTO_STATIC_CACHING}" == "1" ]]; then
            export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento1.conf}"
        else
            export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento1-dev.conf}"
        fi
    fi
    
    # Magento 2 specific configuration
    if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
        if [[ "${ROLL_MAGENTO_STATIC_CACHING}" == "1" ]]; then
            if [[ "${ROLL_ADMIN_AUTOLOGIN}" == "1" ]]; then
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-autologin.conf}"
            else
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2.conf}"
            fi
        else
            if [[ "${ROLL_ADMIN_AUTOLOGIN}" == "1" ]]; then
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-dev-autologin.conf}"
            else
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-dev.conf}"
            fi
        fi
    fi
    # env.cmd used to export these unconditionally; the compose fragments still interpolate them
    # for every environment type, so keep them defined even when nothing derived a value.
    export NGINX_TEMPLATE="${NGINX_TEMPLATE:-}"
    export NGINX_PUBLIC="${NGINX_PUBLIC:-}"
}

## Validate configuration file without loading
function validateConfig() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]]; then
        config_file="$(locateEnvPath)/.env.roll"
    fi
    
    # Initialize schema if not done
    initConfigSchema
    
    loadConfigFromFile "$config_file" "true"
}

## Get configuration value
function getConfig() {
    local key="$1"
    local default_value="$2"
    
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 ]]; then
        echo "${ROLL_CONFIG_CACHE_VALUES[$index]}"
    elif [[ -n "${!key}" ]]; then
        echo "${!key}"
    else
        echo "${default_value}"
    fi
}

## Set configuration value
function setConfig() {
    local key="$1"
    local value="$2"
    
    if validateConfigValue "$key" "$value"; then
        setConfigValue "$key" "$value"
        return 0
    else
        return 1
    fi
}

## Display configuration summary
function showConfig() {
    local filter="${1:-}"
    
    echo -e "\033[33mRoll Configuration:\033[0m"
    echo "Environment: ${ROLL_ENV_NAME:-<not set>} (${ROLL_ENV_TYPE:-<not set>})"
    echo "Platform: ${ROLL_ENV_SUBT:-<not set>}"
    
    # Show loaded configuration files
    if [[ ${#ROLL_CONFIG_LOADED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo -e "\033[33mLoaded configuration files:\033[0m"
        local loaded_file
        for loaded_file in "${ROLL_CONFIG_LOADED_FILES[@]}"; do
            if [[ "$loaded_file" =~ ${ROLL_HOME_DIR} ]]; then
                echo "  ${loaded_file} (global)"
            else
                echo "  ${loaded_file} (project)"
            fi
        done
    fi
    
    echo ""
    
    local i=0
    while [[ $i -lt ${#ROLL_CONFIG_CACHE_KEYS[@]} ]]; do
        local key="${ROLL_CONFIG_CACHE_KEYS[$i]}"
        local value="${ROLL_CONFIG_CACHE_VALUES[$i]}"
        
        if [[ -n "$filter" && ! "$key" =~ $filter ]]; then
            i=$((i + 1))
            continue
        fi
        
        printf "  %-30s = %s\n" "$key" "$value"
        i=$((i + 1))
    done
}

## Check for configuration conflicts
function checkConfigConflicts() {
    local errors=0
    
    # Redis vs Dragonfly conflict
    if [[ "$(getConfig ROLL_REDIS 0)" == "1" && "$(getConfig ROLL_DRAGONFLY 0)" == "1" ]]; then
        error "Configuration conflict: ROLL_REDIS and ROLL_DRAGONFLY cannot both be enabled"
        errors=$((errors + 1))
    fi
    
    # Environment type specific validations
    if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
        if [[ "$(getConfig ROLL_ELASTICSEARCH 0)" == "1" && "$(getConfig ROLL_OPENSEARCH 0)" == "1" ]]; then
            warning "Both Elasticsearch and OpenSearch are enabled - this may cause conflicts"
        fi
    fi
    
    # Database distribution validation
    local db_dist="$(getConfig DB_DISTRIBUTION mariadb)"
    if [[ "$db_dist" != "mysql" && "$db_dist" != "mariadb" ]]; then
        error "DB_DISTRIBUTION must be either 'mysql' or 'mariadb', got: $db_dist"
        errors=$((errors + 1))
    fi
    
    return $errors
}

## Legacy compatibility wrapper - replace old loadEnvConfig calls
function loadEnvConfig() {
    local env_path="$1"
    loadRollConfig "$env_path"
} 