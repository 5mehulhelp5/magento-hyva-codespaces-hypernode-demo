#!/bin/bash

set -eu

# ======================================================================================
# Environment and Service Configuration
# ======================================================================================
CODESPACES_REPO_ROOT="${CODESPACES_REPO_ROOT:=$(pwd)}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:=password}"
MAGENTO_ADMIN_USERNAME="${MAGENTO_ADMIN_USERNAME:=admin}"
MAGENTO_ADMIN_PASSWORD="${MAGENTO_ADMIN_PASSWORD:=password1}"
MAGENTO_ADMIN_EMAIL="${MAGENTO_ADMIN_EMAIL:=admin@example.com}"
INSTALL_MAGENTO="${INSTALL_MAGENTO:-YES}"

# ======================================================================================
# Supervisor Services (Nginx, MariaDB, Redis)
# ======================================================================================
echo "Configuring Supervisor services..."

# Create runtime directory for Nginx before starting it
sudo mkdir -p /var/run/nginx

# Copy config files
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/nginx.conf" /etc/nginx/nginx.conf
sudo sed -i "s|__CODESPACES_REPO_ROOT__|${CODESPACES_REPO_ROOT}|g" /etc/nginx/nginx.conf
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-php-fpm.conf" /etc/supervisor/conf.d/
sudo sed -i "s|\$CODESPACES_REPO_ROOT|${CODESPACES_REPO_ROOT}|g" /etc/supervisor/conf.d/sp-php-fpm.conf
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-redis.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/mysql.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-nginx.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/mysql.cnf" /etc/mysql/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/client.cnf" /etc/mysql/conf.d/

# Ensure supervisor runs in daemon mode
if sudo grep -q "^nodaemon=true" /etc/supervisor/supervisord.conf; then
    sudo sed -i '/^nodaemon=true/d' /etc/supervisor/supervisord.conf
fi

# More robust check for starting/reloading supervisor
SUPERVISOR_PID_FILE="/var/run/supervisord.pid"
if [ -f "$SUPERVISOR_PID_FILE" ] && ps -p $(cat $SUPERVISOR_PID_FILE) > /dev/null 2>&1; then
    echo "Supervisor is running. Reloading configuration..."
    sudo supervisorctl reread
    sudo supervisorctl update
else
    echo "Supervisor not running or PID file is stale. Starting new daemon..."
    sudo rm -f /var/run/supervisor.sock "$SUPERVISOR_PID_FILE"
    sudo /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
fi

# ======================================================================================
# Wait for Services to become ready
# ======================================================================================

# Wait for MariaDB
echo "Waiting for MySQL to be ready..."
if ! timeout 60 bash -c 'until sudo mysqladmin ping --silent; do echo "Waiting..." && sleep 2; done'; then
    echo "Error: MySQL did not become available within 60 seconds."
    exit 1
fi
echo "MySQL is ready!"

# Wait for OpenSearch
echo "Waiting for OpenSearch to be ready..."
if ! timeout 120 bash -c 'until curl -s -f http://localhost:9200/_cluster/health?wait_for_status=yellow > /dev/null; do echo "Waiting..." && sleep 5; done'; then
    echo "Error: OpenSearch did not become available within 120 seconds."
    docker logs $OPENSEARCH_CONTAINER
    exit 1
fi
echo "OpenSearch is ready!"


# ======================================================================================
# Magento Setup / Database Import
# ======================================================================================
cd "${CODESPACES_REPO_ROOT}"

if [ -f ".devcontainer/db-installed.flag" ]; then 
  echo "Magento already installed, skipping installation/import."
    echo "Running Hyvä Build"
    n98-magerun2 dev:theme:build-hyva
    exit 1
else
   echo "Updating PHP Memory Limit"
   echo "memory_limit=2G" | sudo tee -a /usr/local/etc/php/conf.d/docker-fpm.ini

  # Decide whether to run a fresh install or import a database
  if [ "${INSTALL_MAGENTO}" = "YES" ]; then
    echo "============ Installing New Magento Instance ============"
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'password'; FLUSH PRIVILEGES;"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS magento2;"

    url="https://${CODESPACE_NAME}-8080.app.github.dev/"
    echo "Installing Magento with URL: $url"
    
    php -d memory_limit=-1 bin/magento setup:install \
      --db-name='magento2' \
      --db-user='root' \
      --db-host='127.0.0.1' \
      --db-password="${MYSQL_ROOT_PASSWORD}" \
      --base-url="$url" \
      --backend-frontname='admin' \
      --admin-user="${MAGENTO_ADMIN_USERNAME}" \
      --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
      --admin-email="${MAGENTO_ADMIN_EMAIL}" \
      --admin-firstname='Admin' \
      --admin-lastname='User' \
      --language='en_GB' \
      --currency='GBP' \
      --timezone='Europe/London' \
      --use-rewrites='1' \
      --use-secure='1' \
      --base-url-secure="$url" \
      --use-secure-admin='1' \
      --session-save='redis' \
      --session-save-redis-host='127.0.0.1' \
      --session-save-redis-port='6379' \
      --cache-backend='redis' \
      --cache-backend-redis-server='127.0.0.1' \
      --cache-backend-redis-db='1' \
      --page-cache='redis' \
      --page-cache-redis-server='127.0.0.1' \
      --page-cache-redis-db='2' \
      --search-engine='opensearch' \
      --opensearch-host='localhost' \
      --opensearch-port='9200'

    echo "============ Configuring Magento =========="
    php -d memory_limit=-1 bin/magento deploy:mode:set developer
    php -d memory_limit=-1 bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth Magento_TwoFactorAuth

sudo mysql -e 'use magento2; UPDATE `design_config_grid_flat` SET `theme_theme_id` = "5" WHERE `theme_theme_id` = "3"';
sudo mysql -e 'use magento2; UPDATE `core_config_data` SET `value` = "5" WHERE `path` = "design/theme/theme_id" AND `scope_id` = 0 AND `scope` = "default";'

        echo "============ Magento Installation Complete ============"
  else
    echo "============ Copying env.php to Magento ============"
    cp ${CODESPACES_REPO_ROOT}/.devcontainer/config/env.php ${CODESPACES_REPO_ROOT}/app/etc/env.php
    echo "============ Importing Staging Database ============"
    if [ -z "${WASABI_AUTH_KEY:-}" ] || [ -z "${WASABI_AUTH_SECRET:-}" ]; then
        echo "WARNING: Wasabi credentials not set. Cannot import database."
    else
       # echo "Downloading database from Wasabi..."
       # wget -q https://dl.minio.io/client/mc/release/linux-amd64/mc
       # chmod +x mc
       # ./mc alias set --api S3v4 wasabi https://s3.eu-west-1.wasabisys.com "${WASABI_AUTH_KEY}" "${WASABI_AUTH_SECRET}" > /dev/null
       # ./mc cp wasabi/develo.hyvademo/hyva.sql.zip ./hyva.sql.zip
       # unzip -o ./hyva.sql.zip
        
        #echo "Updating and importing database..."
       # url="https://${CODESPACE_NAME}-8080.app.github.dev/"
       #sed "s|https://bam-hyva.develo.design/|$url|g" ${CODESPACES_REPO_ROOT}/bamford_cleansed_hyva.sql > ${CODESPACES_REPO_ROOT}/bamford_cleansed_hyva_updated.sql
      # mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" magento2 < "bamford_cleansed_hyva_updated.sql"
       sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'password'; FLUSH PRIVILEGES;"
       # echo "Database imported successfully."

      # echo "Fetching Media Files"        
      # ./mc cp wasabi/clients.bamford/bam_media.zip ${CODESPACES_REPO_ROOT}/bam_media.zip
      # unzip -o ${CODESPACES_REPO_ROOT}/bam_media.zip -d ${CODESPACES_REPO_ROOT}/pub/ && rm ./bam_media.zip
        # Configure Magento after DB import
     #   php -d memory_limit=-1 bin/magento setup:upgrade
     #   php -d memory_limit=-1 bin/magento config:set catalog/search/engine opensearch
     #   php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_hostname localhost
     #   php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_port 9200
     #   php -d memory_limit=-1 bin/magento cache:flush
     #   rm -rf ${CODESPACES_REPO_ROOT}/pub/static/frontend
    fi
  fi
fi

## MISC
echo "Patch the X-frame-options to allow quick view"
url="https://${CODESPACE_NAME}-8080.app.github.dev/"
target="${CODESPACES_REPO_ROOT}/vendor/magento/framework/App/Response/HeaderProvider/XFrameOptions.php"
sed -i "s|\$this->headerValue = \$xFrameOpt;|\$this->headerValue = '${url}';|" "$target"

echo "============ Environment Ready =========="
echo "All services started successfully!"
echo "You can check service status with: sudo supervisorctl status"
echo "And Docker containers with: docker ps"
echo "Have an awesome time!"

## Start AI Task Runner
if [ ! -f ".devcontainer/db-installed.flag" ]; then
    .devcontainer/start_ai_task.sh
fi

touch "${CODESPACES_REPO_ROOT}/.devcontainer/db-installed.flag"