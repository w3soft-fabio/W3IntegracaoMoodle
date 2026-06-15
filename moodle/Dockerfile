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
    && a2enmod rewrite headers expires \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html/* \
    && git clone --branch MOODLE_405_STABLE --depth 1 https://github.com/moodle/moodle.git /var/www/html \
    && mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata

COPY php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY config.php /var/www/html/config.php

RUN chown www-data:www-data /var/www/html/config.php

WORKDIR /var/www/html
