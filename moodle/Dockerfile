FROM php:8.3-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    curl \
    default-mysql-client \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        soap \
        exif \
        opcache \
        mbstring \
        curl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && a2enmod rewrite headers expires \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html/* \
    && git clone --branch MOODLE_500_STABLE --depth 1 https://github.com/moodle/moodle.git /var/www/html \
    && curl -fsSL "https://download.moodle.org/download.php/direct/langpack/5.0/pt_br.zip" -o /tmp/pt_br.zip \
    && unzip /tmp/pt_br.zip -d /var/www/html/lang \
    && rm /tmp/pt_br.zip \
    && mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata

COPY php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY config.php /var/www/html/config.php
COPY bootstrap/provision.php /var/www/html/bootstrap/provision.php
COPY docker-entrypoint.sh /usr/local/bin/moodle-entrypoint

RUN chown www-data:www-data /var/www/html/config.php \
    && chown -R www-data:www-data /var/www/html/bootstrap \
    && chmod +x /usr/local/bin/moodle-entrypoint

WORKDIR /var/www/html

ENTRYPOINT ["moodle-entrypoint"]
CMD ["apache2-foreground"]
