<?php

function provision_webservice(stdClass $admin): void {
    ensure_webservice_settings();
    $functions = resolve_ws_functions(env_required('MOODLE_WS_FUNCTIONS'));
    $service = ensure_service($functions);
    authorize_service_user($service, $admin);
    $token = ensure_token($service, $admin);
    write_token_file($token);
}
