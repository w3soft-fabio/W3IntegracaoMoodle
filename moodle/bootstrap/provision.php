<?php

require_once(__DIR__ . '/provisioning-functions.php');
require_once(__DIR__ . '/provision-site.php');
require_once(__DIR__ . '/provision-integrations.php');
require_once(__DIR__ . '/provision-enrolment.php');
require_once(__DIR__ . '/provision-webservice.php');

$firstinstall = env_bool('MOODLE_BOOTSTRAP_FIRST_INSTALL', false);

bootstrap_log('Starting tenant provisioning.');
$admin = provision_site($firstinstall);
provision_integrations();
provision_enrolment();
provision_webservice($admin);
bootstrap_log('Tenant provisioning finished.');
