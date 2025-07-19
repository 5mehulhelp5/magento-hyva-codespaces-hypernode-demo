#!/bin/bash

set -eu

# Define primary variables
CODESPACES_REPO_ROOT="${CODESPACES_REPO_ROOT:=$(pwd)}"
MAGENTO_EDITION="${MAGENTO_EDITION:=community}"
MAGENTO_VERSION="${MAGENTO_VERSION:=2.4.7-p5}"
COMPOSER_COMMAND="php -d memory_limit=-1 $(which composer)"
INSTALL_MAGENTO="${INSTALL_MAGENTO:-YES}"

# Change to the repository root directory
cd "${CODESPACES_REPO_ROOT}"

echo "============ 1. Setup Magento Environment =========="
# Check for Magento credentials before attempting to use them
if [ INSTALL_MAGENTO == "YES" && -z "${MAGENTO_COMPOSER_AUTH_USER:-}" ] || [ -z "${MAGENTO_COMPOSER_AUTH_PASS:-}" ]; then
  echo "ERROR: Please set the MAGENTO_COMPOSER_AUTH_USER and MAGENTO_COMPOSER_AUTH_PASS"
  echo "secrets in your Codespace or repository settings."
  exit 1
fi

# Handle Magento project creation if composer.json doesn't exist
if [ ! -f composer.json ]; then
  echo "**** Creating Magento project ${MAGENTO_VERSION} ****"
  # Configure Composer authentication globally for the container
  ${COMPOSER_COMMAND} config -g -a http-basic.repo.magento.com "${MAGENTO_COMPOSER_AUTH_USER}" "${MAGENTO_COMPOSER_AUTH_PASS}"
  
  # Create Magento project in a temporary directory
  # The --no-install flag prevents composer from installing dependencies immediately
  ${COMPOSER_COMMAND} create-project --no-install --repository-url=https://repo.magento.com/ magento/project-${MAGENTO_EDITION}-edition=${MAGENTO_VERSION} .
  
  # Create a local auth.json for future composer operations within the project
  echo '{ "http-basic": { "repo.magento.com": { "username": "'"${MAGENTO_COMPOSER_AUTH_USER}"'", "password": "'"${MAGENTO_COMPOSER_AUTH_PASS}"'" } } }' > auth.json
fi

echo "**** Running composer install ****"
${COMPOSER_COMMAND} install --no-dev --optimize-autoloader

echo "**** Installing n98-magerun2 ****"
curl -L https://files.magerun.net/n98-magerun2.phar --output bin/magerun2
chmod +x bin/magerun2

echo "============ 2. Setup Complete =========="
