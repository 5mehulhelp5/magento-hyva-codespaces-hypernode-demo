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

# Docker container names
MAILPIT_CONTAINER="mailpit"
OPENSEARCH_CONTAINER="opensearch-node"
PHPMYADMIN_CONTAINER="phpmyadmin"

echo "============ Starting Services =========="

# ======================================================================================
# Docker Container Management
# ======================================================================================

echo "============ 1. Setup Magento Environment =========="
# Check for Magento credentials before attempting to use them
if [ "$INSTALL_MAGENTO" == "YES" ] && ([ -z "${MAGENTO_COMPOSER_AUTH_USER:-}" ] || [ -z "${MAGENTO_COMPOSER_AUTH_PASS:-}" ]); then
  echo "ERROR: Please set the MAGENTO_COMPOSER_AUTH_USER and MAGENTO_COMPOSER_AUTH_PASS"
  echo "secrets in your Codespace or repository settings."
  exit 1
fi

echo "**** Running composer install ****"
${COMPOSER_COMMAND} install --no-dev --optimize-autoloader --ignore-platform-reqs
bin/magento sampledata:deploy

# AI Packages
sudo npm install -g @google/gemini-cli
sudo npm install -g @anthropic-ai/claude-code

# Function to start a Docker container if not running
start_container() {
    local container_name=$1
    shift
    local docker_run_cmd=("$@")
    
    if [ ! "$(docker ps -q -f name=^/${container_name}$)" ]; then
        if [ "$(docker ps -aq -f status=exited -f name=^/${container_name}$)" ]; then
            echo "Removing stopped ${container_name} container..."
            docker rm $container_name
        fi
        echo "Starting ${container_name} container..."
        "${docker_run_cmd[@]}"
    else
        echo "${container_name} container is already running."
    fi
}

# Start Mailpit Container
start_container $MAILPIT_CONTAINER \
    docker run -d --restart unless-stopped --name $MAILPIT_CONTAINER \
    -p 8025:8025 -p 1025:1025 axllent/mailpit

# Start OpenSearch Container with security disabled
start_container $OPENSEARCH_CONTAINER \
    docker run -d --restart unless-stopped --name $OPENSEARCH_CONTAINER \
    -p 9200:9200 -p 9600:9600 \
    -e "discovery.type=single-node" \
    -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" \
    -e "DISABLE_INSTALL_DEMO_CONFIG=true" \
    -e "plugins.security.disabled=true" \
    opensearchproject/opensearch:2.19.2

# Start phpMyAdmin Container - connects to the main container via host.docker.internal
start_container $PHPMYADMIN_CONTAINER \
    docker run -d --restart unless-stopped --name $PHPMYADMIN_CONTAINER \
    -p 8081:80 \
    -e PMA_HOST=host.docker.internal \
    -e PMA_PORT=3306 \
    -e PMA_USER=root \
    -e PMA_PASSWORD=${MYSQL_ROOT_PASSWORD} \
    phpmyadmin/phpmyadmin

echo "============ 2. Setup Complete =========="
