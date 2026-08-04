<?php

function provision_integrations(): void {
    ensure_bigbluebutton_settings();
    ensure_smtp_settings();
}
