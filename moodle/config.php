<?php

unset($CFG);
global $CFG;
$CFG = new stdClass();

function moodle_env_required(string $name): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        throw new RuntimeException("Missing required environment variable: {$name}");
    }

    return $value;
}

function moodle_env_optional(string $name, string $default): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return $value;
}

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = moodle_env_optional('MOODLE_DB_HOST', 'db');
$CFG->dbname    = moodle_env_required('MOODLE_DB_NAME');
$CFG->dbuser    = moodle_env_required('MOODLE_DB_USER');
$CFG->dbpass    = moodle_env_required('MOODLE_DB_PASSWORD');
$CFG->prefix    = 'mdl_';

$CFG->dboptions = [
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
];

$CFG->wwwroot   = moodle_env_required('MOODLE_URL');
$CFG->dataroot  = moodle_env_optional('MOODLE_DATAROOT', '/var/www/moodledata');
$CFG->admin     = 'admin';
$CFG->lang      = moodle_env_optional('MOODLE_DEFAULT_LANG', 'pt_br');
$CFG->langotherroot = __DIR__ . '/lang';

$publicSlug = getenv('MOODLE_PUBLIC_SLUG');

if ($publicSlug !== false && $publicSlug !== '') {
    $sessionSlug = preg_replace('/[^a-zA-Z0-9_]/', '_', $publicSlug);
    $CFG->sessioncookie = 'MoodleSession_' . $sessionSlug;
}
$redisHost = moodle_env_optional('MOODLE_REDIS_HOST', '');

if ($redisHost !== '') {
    $redisPrefix = moodle_env_required('MOODLE_REDIS_PREFIX');

    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = $redisHost;
    $CFG->session_redis_port = (int) moodle_env_optional('MOODLE_REDIS_PORT', '6379');
    $CFG->session_redis_database = (int) moodle_env_optional('MOODLE_REDIS_DATABASE', '0');
    $CFG->session_redis_prefix = $redisPrefix . 'session_';
    $CFG->session_redis_acquire_lock_timeout = 120;
    $CFG->session_redis_acquire_lock_retry = 100;
    $CFG->session_redis_lock_expire = 7200;

    $redisPassword = getenv('MOODLE_REDIS_PASSWORD');

    if ($redisPassword !== false && $redisPassword !== '') {
        $CFG->session_redis_auth = $redisPassword;
    }
}
$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');
