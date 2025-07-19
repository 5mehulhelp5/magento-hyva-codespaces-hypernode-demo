# Use the "bullseye" based PHP image, which is compatible with MariaDB 10.6
FROM php:8.2-fpm-bullseye

# Environment variables to allow non-interactive installation
ENV MYSQL_ROOT_PASSWORD=password
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    apt-utils \
    lsb-release \
    ca-certificates \
    curl \
    wget \
    gnupg \
    python3 \
    python-is-python3 \
    libmariadb-dev \
    rsync \
    libnss3-dev \
    openssh-client \
    mc \
    gcc \
    make \
    autoconf \
    libc-dev \
    pkg-config \
    libmcrypt-dev \
    supervisor \
    nginx \
    redis-server \
    zip \
    unzip \
    git \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libxpm-dev \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    libxslt1-dev \
    libicu-dev \
    libmagickwand-dev \
    vim \
    sudo

# Install PHP extensions required for Magento
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm && \
    docker-php-ext-install -j$(nproc) \
        gd \
        bcmath \
        intl \
        mbstring \
        soap \
        xml \
        zip \
        pdo_mysql \
        mysqli \
        sockets \
        xsl

# Install additional PHP extensions via PECL
RUN pecl install imagick redis xdebug && \
    docker-php-ext-enable imagick redis xdebug

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install MariaDB Server 10.6 (for Magento 2.4 compatibility)
RUN apt-get update && \
    mkdir -p /etc/apt/keyrings && \
    curl -o /etc/apt/keyrings/mariadb-keyring.pgp 'https://mariadb.org/mariadb_release_signing_key.pgp' && \
    echo "deb [signed-by=/etc/apt/keyrings/mariadb-keyring.pgp] https://deb.mariadb.org/10.6/debian bullseye main" | tee /etc/apt/sources.list.d/mariadb.list && \
    apt-get update && \
    echo "mariadb-server-10.6 mysql-server/root_password password ${MYSQL_ROOT_PASSWORD}" | debconf-set-selections && \
    echo "mariadb-server-10.6 mysql-server/root_password_again password ${MYSQL_ROOT_PASSWORD}" | debconf-set-selections && \
    apt-get install -y mariadb-server mariadb-client && \
    mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && \
    apt-get install -y nodejs

# Install Java, a dependency for OpenSearch
RUN apt-get update && apt-get install -y openjdk-17-jdk-headless
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Prepare for OpenSearch installation by adding the repository and key
RUN curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-2.x.list && \
    apt-get update

# Install n98-magerun2
RUN wget https://files.magerun.net/n98-magerun2.phar && \
    chmod +x ./n98-magerun2.phar && \
    mv ./n98-magerun2.phar /usr/local/bin/n98-magerun2

# Create vscode user
RUN groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid vscode --shell /bin/bash --create-home vscode && \
    echo 'vscode ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Install Docker client to manage Mailpit (not the daemon)
RUN curl -fsSL https://get.docker.com -o get-docker.sh && \
    sh get-docker.sh && \
    rm get-docker.sh && \
    usermod -aG docker vscode

# Clean up
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Switch to vscode user
USER vscode

# Set working directory
WORKDIR /workspaces/BamfordDevelo
