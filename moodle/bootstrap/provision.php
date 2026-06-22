<?php

define('CLI_SCRIPT', true);

require_once(__DIR__ . '/../config.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/webservice/lib.php');

function bootstrap_log(string $message): void {
    fwrite(STDOUT, "[moodle-bootstrap] {$message}" . PHP_EOL);
}

function bootstrap_fail(string $message): never {
    fwrite(STDERR, "[moodle-bootstrap] ERROR: {$message}" . PHP_EOL);
    exit(1);
}

function env_required(string $name): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        bootstrap_fail("Missing required environment variable: {$name}");
    }

    return $value;
}

function env_default(string $name, string $default): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return $value;
}

function env_bool(string $name, bool $default): bool {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
}

function split_csv(string $value): array {
    $items = array_map('trim', explode(',', $value));
    return array_values(array_filter($items, static fn(string $item): bool => $item !== ''));
}

function update_site_identity(): void {
    global $DB;

    $fullname = env_required('MOODLE_SITE_FULLNAME');
    $shortname = env_required('MOODLE_SITE_SHORTNAME');
    $summary = env_default('MOODLE_SITE_SUMMARY', '');
    $supportemail = env_required('MOODLE_SUPPORT_EMAIL');
    $timezone = env_required('MOODLE_ADMIN_TIMEZONE');

    $site = $DB->get_record('course', ['id' => SITEID], '*', MUST_EXIST);
    $changed = false;

    foreach (['fullname' => $fullname, 'shortname' => $shortname, 'summary' => $summary] as $field => $value) {
        if ((string)$site->{$field} !== $value) {
            $site->{$field} = $value;
            $changed = true;
        }
    }

    if ($changed) {
        $site->timemodified = time();
        $DB->update_record('course', $site);
        bootstrap_log("Updated site identity.");
    } else {
        bootstrap_log("Site identity already up to date.");
    }

    set_config('supportemail', $supportemail);
    set_config('timezone', $timezone);
}

function update_admin_user(bool $firstinstall): stdClass {
    global $DB;

    $username = env_default('MOODLE_ADMIN_USER', 'admin');
    $admin = $DB->get_record('user', ['username' => $username, 'deleted' => 0], '*', MUST_EXIST);

    $user = (object)[
        'id' => $admin->id,
        'firstname' => env_required('MOODLE_ADMIN_FIRSTNAME'),
        'lastname' => env_required('MOODLE_ADMIN_LASTNAME'),
        'email' => env_required('MOODLE_ADMIN_EMAIL'),
        'city' => env_required('MOODLE_ADMIN_CITY'),
        'country' => env_required('MOODLE_ADMIN_COUNTRY'),
        'timezone' => env_required('MOODLE_ADMIN_TIMEZONE'),
    ];

    $resetpassword = env_bool('MOODLE_ADMIN_RESET_PASSWORD', false);
    if ($resetpassword) {
        $user->password = env_required('MOODLE_ADMIN_PASSWORD');
    }

    user_update_user($user, $resetpassword, false);

    if ($firstinstall && env_bool('MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL', true)) {
        set_user_preference('auth_forcepasswordchange', 1, $admin->id);
        bootstrap_log("Admin password change will be required on first login.");
    }

    bootstrap_log("Admin user profile configured: {$username}.");
    return $DB->get_record('user', ['id' => $admin->id], '*', MUST_EXIST);
}

function ensure_webservice_settings(): void {
    global $CFG;

    set_config('enablewebservices', '1');
    $CFG->enablewebservices = '1';

    $protocols = empty($CFG->webserviceprotocols) ? [] : split_csv($CFG->webserviceprotocols);
    if (!in_array('rest', $protocols, true)) {
        $protocols[] = 'rest';
        set_config('webserviceprotocols', implode(',', $protocols));
        $CFG->webserviceprotocols = implode(',', $protocols);
        bootstrap_log("Enabled REST webservice protocol.");
    } else {
        bootstrap_log("REST webservice protocol already enabled.");
    }
}

function ensure_service(array $functions): stdClass {
    global $DB;

    $manager = new webservice();
    $name = env_default('MOODLE_WS_SERVICE_NAME', 'W3Soft Student Sync');
    $shortname = env_default('MOODLE_WS_SERVICE_SHORTNAME', 'w3soft_student_sync');

    foreach ($functions as $function) {
        if (!$DB->record_exists('external_functions', ['name' => $function])) {
            bootstrap_fail("External function does not exist in this Moodle installation: {$function}");
        }
    }

    $service = $manager->get_external_service_by_shortname($shortname);
    if (!$service) {
        $service = (object)[
            'name' => $name,
            'enabled' => 1,
            'requiredcapability' => '',
            'restrictedusers' => 1,
            'component' => '',
            'shortname' => $shortname,
            'downloadfiles' => 0,
            'uploadfiles' => 0,
        ];
        $service->id = $manager->add_external_service($service);
        bootstrap_log("Created external service: {$shortname}.");
    } else {
        $service->name = $name;
        $service->enabled = 1;
        $service->restrictedusers = 1;
        $service->requiredcapability = $service->requiredcapability ?? '';
        $service->downloadfiles = 0;
        $service->uploadfiles = 0;
        $manager->update_external_service($service);
        bootstrap_log("External service already exists: {$shortname}.");
    }

    foreach ($functions as $function) {
        if (!$manager->service_function_exists($function, $service->id)) {
            $manager->add_external_function_to_service($function, $service->id);
            bootstrap_log("Added function to service: {$function}.");
        }
    }

    return $manager->get_external_service_by_shortname($shortname, MUST_EXIST);
}

function ensure_ws_user(): stdClass {
    global $DB;

    $username = core_text::strtolower(env_required('MOODLE_WS_USER_USERNAME'));
    $password = env_required('MOODLE_WS_USER_PASSWORD');
    $existing = $DB->get_record('user', ['username' => $username, 'deleted' => 0]);

    $user = (object)[
        'username' => $username,
        'firstname' => env_required('MOODLE_WS_USER_FIRSTNAME'),
        'lastname' => env_required('MOODLE_WS_USER_LASTNAME'),
        'email' => env_required('MOODLE_WS_USER_EMAIL'),
        'city' => env_required('MOODLE_WS_USER_CITY'),
        'country' => env_required('MOODLE_WS_USER_COUNTRY'),
        'timezone' => env_required('MOODLE_WS_USER_TIMEZONE'),
        'auth' => 'manual',
        'confirmed' => 1,
        'mnethostid' => 1,
    ];

    if ($existing) {
        $user->id = $existing->id;
        $resetpassword = env_bool('MOODLE_WS_USER_RESET_PASSWORD', false);
        if ($resetpassword) {
            $user->password = $password;
        }
        user_update_user($user, $resetpassword, false);
        bootstrap_log("Technical webservice user already exists: {$username}.");
        return $DB->get_record('user', ['id' => $existing->id], '*', MUST_EXIST);
    }

    $user->password = $password;
    $userid = user_create_user($user, true, false);
    bootstrap_log("Created technical webservice user: {$username}.");
    return $DB->get_record('user', ['id' => $userid], '*', MUST_EXIST);
}

function ensure_ws_role(stdClass $wsuser): int {
    global $DB;

    $shortname = env_default('MOODLE_WS_ROLE_SHORTNAME', 'w3soft_ws_integration');
    $name = env_default('MOODLE_WS_ROLE_NAME', 'W3Soft webservice integration');
    $description = 'Role managed by Moodle container bootstrap for REST integrations.';
    $systemcontext = context_system::instance();

    $role = $DB->get_record('role', ['shortname' => $shortname]);
    if ($role) {
        $role->name = $name;
        $role->description = $description;
        $DB->update_record('role', $role);
        $roleid = (int)$role->id;
        bootstrap_log("Webservice role already exists: {$shortname}.");
    } else {
        $roleid = create_role($name, $shortname, $description);
        bootstrap_log("Created webservice role: {$shortname}.");
    }

    set_role_contextlevels($roleid, [CONTEXT_SYSTEM]);

    $capabilities = [
        'webservice/rest:use',
        'moodle/webservice:createtoken',
        'moodle/course:view',
        'moodle/course:viewhiddencourses',
        'moodle/user:create',
        'moodle/user:viewdetails',
        'moodle/user:viewhiddendetails',
        'moodle/course:useremail',
        'moodle/user:update',
        'enrol/manual:enrol',
    ];

    $extra = env_default('MOODLE_WS_EXTRA_CAPABILITIES', '');
    if ($extra !== '') {
        $capabilities = array_merge($capabilities, split_csv($extra));
    }

    foreach (array_unique($capabilities) as $capability) {
        if (!get_capability_info($capability)) {
            bootstrap_fail("Capability does not exist in this Moodle installation: {$capability}");
        }
        assign_capability($capability, CAP_ALLOW, $roleid, $systemcontext->id, true);
    }

    if (!$DB->record_exists('role_assignments', [
        'roleid' => $roleid,
        'contextid' => $systemcontext->id,
        'userid' => $wsuser->id,
    ])) {
        role_assign($roleid, $wsuser->id, $systemcontext->id);
        bootstrap_log("Assigned webservice role to user: {$wsuser->username}.");
    }

    $targetshortname = env_default('MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME', 'student');
    $targetrole = $DB->get_record('role', ['shortname' => $targetshortname], '*', MUST_EXIST);
    if (!$DB->record_exists('role_allow_assign', ['roleid' => $roleid, 'allowassign' => $targetrole->id])) {
        core_role_set_assign_allowed($roleid, $targetrole->id);
        bootstrap_log("Allowed webservice role to assign target role: {$targetshortname}.");
    }

    accesslib_clear_all_caches(true);
    return $roleid;
}

function authorize_service_user(stdClass $service, stdClass $wsuser): void {
    global $DB;

    $record = $DB->get_record('external_services_users', [
        'externalserviceid' => $service->id,
        'userid' => $wsuser->id,
    ]);

    $iprestriction = env_default('MOODLE_WS_USER_IP_RESTRICTION', '');
    $validuntil = (int)env_default('MOODLE_WS_USER_VALID_UNTIL', '0');

    if ($record) {
        $record->iprestriction = $iprestriction;
        $record->validuntil = $validuntil;
        $DB->update_record('external_services_users', $record);
        bootstrap_log("Technical user already authorized for service.");
        return;
    }

    $DB->insert_record('external_services_users', (object)[
        'externalserviceid' => $service->id,
        'userid' => $wsuser->id,
        'iprestriction' => $iprestriction,
        'validuntil' => $validuntil,
        'timecreated' => time(),
    ]);
    bootstrap_log("Authorized technical user for service.");
}

function ensure_token(stdClass $service, stdClass $wsuser, stdClass $admin): string {
    global $DB;

    $now = time();
    $token = $DB->get_record_sql(
        'SELECT *
           FROM {external_tokens}
          WHERE userid = :userid
            AND externalserviceid = :serviceid
            AND tokentype = :tokentype
            AND (validuntil IS NULL OR validuntil = 0 OR validuntil > :now)
       ORDER BY id ASC',
        [
            'userid' => $wsuser->id,
            'serviceid' => $service->id,
            'tokentype' => EXTERNAL_TOKEN_PERMANENT,
            'now' => $now,
        ],
        IGNORE_MULTIPLE
    );

    if ($token) {
        bootstrap_log("Reusing active webservice token for service/user.");
        return $token->token;
    }

    $tokenvalue = md5(uniqid((string)random_int(0, PHP_INT_MAX), true));
    $validuntil = (int)env_default('MOODLE_WS_TOKEN_VALID_UNTIL', '0');

    $DB->insert_record('external_tokens', (object)[
        'token' => $tokenvalue,
        'privatetoken' => random_string(64),
        'tokentype' => EXTERNAL_TOKEN_PERMANENT,
        'userid' => $wsuser->id,
        'externalserviceid' => $service->id,
        'sid' => null,
        'contextid' => context_system::instance()->id,
        'creatorid' => $admin->id,
        'iprestriction' => env_default('MOODLE_WS_TOKEN_IP_RESTRICTION', ''),
        'validuntil' => $validuntil,
        'timecreated' => $now,
        'lastaccess' => null,
        'name' => env_default('MOODLE_WS_TOKEN_NAME', 'W3Soft bootstrap token'),
    ]);

    bootstrap_log("Created new webservice token for service/user.");
    return $tokenvalue;
}

function write_token_file(string $token): void {
    $tokenfile = env_default('MOODLE_WS_TOKEN_FILE', '/var/www/moodledata/w3soft/ws-token.txt');

    if (!str_starts_with($tokenfile, '/')) {
        bootstrap_fail('MOODLE_WS_TOKEN_FILE must be an absolute path.');
    }

    $directory = dirname($tokenfile);
    if (!is_dir($directory) && !mkdir($directory, 0700, true) && !is_dir($directory)) {
        bootstrap_fail("Could not create token directory: {$directory}");
    }

    chmod($directory, 0700);

    if (file_put_contents($tokenfile, $token . PHP_EOL, LOCK_EX) === false) {
        bootstrap_fail("Could not write webservice token file: {$tokenfile}");
    }

    chmod($tokenfile, 0600);
    bootstrap_log("Webservice token persisted at: {$tokenfile}");
}

$firstinstall = env_bool('MOODLE_BOOTSTRAP_FIRST_INSTALL', false);

bootstrap_log('Starting tenant provisioning.');
update_site_identity();
$admin = update_admin_user($firstinstall);
ensure_webservice_settings();
$functions = split_csv(env_default('MOODLE_WS_FUNCTIONS', 'core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_user_get_users_by_field,core_user_create_users,enrol_manual_enrol_users'));
$service = ensure_service($functions);
$wsuser = ensure_ws_user();
ensure_ws_role($wsuser);
authorize_service_user($service, $wsuser);
$token = ensure_token($service, $wsuser, $admin);
write_token_file($token);
bootstrap_log('Tenant provisioning finished.');
