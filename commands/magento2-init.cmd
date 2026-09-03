#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${ROLL_DIR}/utils/magento2-init.sh"

# Default Magento version (minimum supported: 2.4.6)
DEFAULT_MAGENTO_VERSION="2.4.x"

# Extract parameters
PROJECT_NAME="${ROLL_PARAMS[0]:-}"
MAGENTO_VERSION="${ROLL_PARAMS[1]:-$DEFAULT_MAGENTO_VERSION}"
TARGET_DIR="${ROLL_PARAMS[2]:-}"

# Phase: resolve version -- validate arguments
m2initValidateArguments

# Phase: create project -- resolve the target directory and create it
m2initResolveTargetDir

echo -e "\033[32mInitializing Magento 2 project: ${PROJECT_NAME}\033[0m"
echo -e "\033[32mMagento version: ${MAGENTO_VERSION}\033[0m"
echo -e "\033[32mTarget directory: ${TARGET_DIR}\033[0m"

m2initCreateProjectDirectory

# Phase: resolve version (software versions) -- determine compatible software versions
echo -e "\033[36m[2/10] Determining compatible software versions...\033[0m"
m2initResolveSoftwareVersions "${MAGENTO_VERSION}"

# Phase: write env -- initialize the environment and align .env.roll with the resolved versions
m2initWriteEnvConfig

# Phase: install -- certificate, environment start, Magento source, setup, configuration, admin user
m2initSignCertificate
m2initStartEnvironment
m2initInstallMagentoSource
m2initSetupMagento
m2initConfigureMagento
m2initReindexMagento
m2initCreateAdminUser

m2initPrintSummary
