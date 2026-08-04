<?php

function provision_site(bool $firstinstall): stdClass {
    update_site_identity();
    ensure_w3_database_settings();
    ensure_access_settings();
    ensure_language_settings();
    return update_admin_user($firstinstall);
}
