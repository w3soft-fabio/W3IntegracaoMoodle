#!/bin/sh

set -eu

MOODLE_DIR="/var/www/html"
MOODLE_DEFAULT_DATAROOT="/var/www/moodledata"
MOODLE_DB_PREFIX="mdl_"

log() {
    printf '%s\n' "[moodle-entrypoint] $*"
}

fail() {
    printf '%s\n' "[moodle-entrypoint] ERROR: $*" >&2
    exit 1
}

env_default() {
    name="$1"
    default="$2"
    eval "value=\${$name:-}"

    if [ -z "$value" ]; then
        export "$name=$default"
    fi
}

require_env() {
    name="$1"
    eval "value=\${$name:-}"

    if [ -z "$value" ]; then
        fail "Missing required environment variable: $name"
    fi
}

run_as_www_data() {
    runuser -u www-data -- "$@"
}

mariadb_query() {
    mariadb \
        -h "$MOODLE_DB_HOST" \
        -u "$MOODLE_DB_USER" \
        "-p$MOODLE_DB_PASSWORD" \
        "$MOODLE_DB_NAME" \
        -N -B \
        -e "$1"
}

wait_for_database() {
    attempts="${MOODLE_DB_WAIT_ATTEMPTS:-60}"
    sleep_seconds="${MOODLE_DB_WAIT_SLEEP_SECONDS:-2}"
    i=1

    log "Waiting for database ${MOODLE_DB_HOST}/${MOODLE_DB_NAME}..."

    while [ "$i" -le "$attempts" ]; do
        if mariadb_query "SELECT 1;" >/dev/null 2>&1; then
            log "Database is available."
            return 0
        fi

        i=$((i + 1))
        sleep "$sleep_seconds"
    done

    fail "Database did not become available after ${attempts} attempts."
}

table_count() {
    mariadb_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE '${MOODLE_DB_PREFIX}%';"
}

config_table_exists() {
    count="$(mariadb_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '${MOODLE_DB_PREFIX}config';")"
    [ "$count" = "1" ]
}

configure_public_path() {
    public_path="${MOODLE_PUBLIC_PATH:-}"

    if [ -z "$public_path" ]; then
        public_path="$(php -r '
            $url = getenv("MOODLE_URL") ?: "";
            $path = parse_url($url, PHP_URL_PATH);
            if ($path !== false && $path !== null && $path !== "" && $path !== "/") {
                echo rtrim($path, "/");
            }
        ')"
    fi

    if [ -n "$public_path" ] && [ "$public_path" != "/" ]; then
        case "$public_path" in
            /*) ;;
            *) public_path="/$public_path" ;;
        esac

        case "$public_path" in
            *[!A-Za-z0-9/_-]*)
                fail "Invalid MOODLE public path: $public_path"
                ;;
        esac

        cat > /etc/apache2/conf-enabled/moodle-public-path.conf <<EOF
Alias ${public_path} /var/www/html
Alias ${public_path}/ /var/www/html/

<Directory /var/www/html>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
    fi
}

set_bootstrap_defaults() {
    env_default MOODLE_AUTO_BOOTSTRAP "1"
    env_default MOODLE_DATAROOT "$MOODLE_DEFAULT_DATAROOT"
    env_default MOODLE_ADMIN_USER "admin"
    env_default MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL "1"
    env_default MOODLE_WS_SERVICE_NAME "W3Soft Student Sync"
    env_default MOODLE_WS_SERVICE_SHORTNAME "w3soft_student_sync"
    env_default MOODLE_WS_FUNCTIONS "core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_user_get_users_by_field,core_user_create_users,enrol_manual_enrol_users"
    env_default MOODLE_WS_ROLE_SHORTNAME "w3soft_ws_integration"
    env_default MOODLE_WS_TOKEN_FILE "$MOODLE_DATAROOT/w3soft/ws-token.txt"
    env_default MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME "student"
}

validate_bootstrap_environment() {
    require_env MOODLE_URL
    require_env MOODLE_DB_HOST
    require_env MOODLE_DB_NAME
    require_env MOODLE_DB_USER
    require_env MOODLE_DB_PASSWORD
    require_env MOODLE_DATAROOT

    require_env MOODLE_SITE_FULLNAME
    require_env MOODLE_SITE_SHORTNAME
    require_env MOODLE_SUPPORT_EMAIL

    require_env MOODLE_ADMIN_USER
    require_env MOODLE_ADMIN_PASSWORD
    require_env MOODLE_ADMIN_FIRSTNAME
    require_env MOODLE_ADMIN_LASTNAME
    require_env MOODLE_ADMIN_EMAIL
    require_env MOODLE_ADMIN_CITY
    require_env MOODLE_ADMIN_COUNTRY
    require_env MOODLE_ADMIN_TIMEZONE

    require_env MOODLE_WS_SERVICE_NAME
    require_env MOODLE_WS_SERVICE_SHORTNAME
    require_env MOODLE_WS_FUNCTIONS
    require_env MOODLE_WS_USER_USERNAME
    require_env MOODLE_WS_USER_PASSWORD
    require_env MOODLE_WS_USER_FIRSTNAME
    require_env MOODLE_WS_USER_LASTNAME
    require_env MOODLE_WS_USER_EMAIL
    require_env MOODLE_WS_USER_CITY
    require_env MOODLE_WS_USER_COUNTRY
    require_env MOODLE_WS_USER_TIMEZONE
    require_env MOODLE_WS_ROLE_SHORTNAME
    require_env MOODLE_WS_TOKEN_FILE
    require_env MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME
}

bootstrap_moodle() {
    case "${MOODLE_AUTO_BOOTSTRAP:-1}" in
        0|false|FALSE|no|NO)
            log "Automatic Moodle bootstrap disabled."
            return 0
            ;;
    esac

    if [ "${1:-}" != "apache2-foreground" ]; then
        log "Skipping automatic Moodle bootstrap for command: ${1:-}"
        return 0
    fi

    set_bootstrap_defaults
    validate_bootstrap_environment

    mkdir -p "$MOODLE_DATAROOT"
    chown www-data:www-data "$MOODLE_DATAROOT"

    wait_for_database

    first_install=0
    if config_table_exists; then
        log "Moodle database is already installed."
    else
        existing_tables="$(table_count)"

        if [ "$existing_tables" != "0" ]; then
            fail "Database has Moodle tables but ${MOODLE_DB_PREFIX}config is missing. Refusing to continue because the install looks incomplete."
        fi

        first_install=1
        log "Moodle database is empty. Running non-interactive installation."

        run_as_www_data php "$MOODLE_DIR/admin/cli/install_database.php" \
            "--lang=${MOODLE_DEFAULT_LANG:-pt_br}" \
            "--adminuser=$MOODLE_ADMIN_USER" \
            "--adminpass=$MOODLE_ADMIN_PASSWORD" \
            "--adminemail=$MOODLE_ADMIN_EMAIL" \
            "--fullname=$MOODLE_SITE_FULLNAME" \
            "--shortname=$MOODLE_SITE_SHORTNAME" \
            "--summary=${MOODLE_SITE_SUMMARY:-}" \
            "--supportemail=$MOODLE_SUPPORT_EMAIL" \
            --agree-license

        log "Moodle database installation finished."
    fi

    export MOODLE_BOOTSTRAP_FIRST_INSTALL="$first_install"

    log "Running Moodle CLI upgrade check."
    run_as_www_data php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive

    log "Running tenant provisioning."
    run_as_www_data php "$MOODLE_DIR/bootstrap/provision.php"

    log "Automatic Moodle bootstrap finished."
}

configure_public_path
bootstrap_moodle "${1:-}"

exec docker-php-entrypoint "$@"
