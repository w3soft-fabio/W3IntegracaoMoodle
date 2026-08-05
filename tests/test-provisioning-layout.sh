#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

grep -q './proxy/Caddyfile:/etc/caddy/Caddyfile:ro' "$project_root/docker-compose.infra.yml"
grep -q 'import /etc/caddy/tenants/\*.caddy' "$project_root/proxy/Caddyfile"

if grep -q 'moodle_[a-z0-9_]*:80' "$project_root/proxy/Caddyfile"; then
    printf '%s\n' 'Base Caddyfile must not contain tenant routes.' >&2
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    caddy_image=''
    if docker image inspect caddy:2-alpine >/dev/null 2>&1; then
        caddy_image='caddy:2-alpine'
    else
        caddy_image=$(docker inspect --format '{{.Image}}' moodle_proxy 2>/dev/null || true)
    fi

    if [ -z "$caddy_image" ]; then
        printf '%s\n' 'SKIP: Caddy image is not available locally'
        printf '%s\n' 'OK: provisioning layout'
        exit 0
    fi

    temporary_root=$(mktemp -d)
    trap 'rm -rf "$temporary_root"' EXIT INT TERM
    mkdir -p "$temporary_root/tenants"

    validate_caddy() {
        docker run --rm \
            -v "$project_root/proxy/Caddyfile:/etc/caddy/Caddyfile:ro" \
            -v "$temporary_root/tenants:/etc/caddy/tenants:ro" \
            "$caddy_image" \
            caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
    }

    validate_caddy
    printf '%s\n' \
        '@tenantexample path /moodle/example/*' \
        'redir /moodle/example /moodle/example/' \
        'handle @tenantexample {' \
        '    reverse_proxy moodle_example:80' \
        '}' > "$temporary_root/tenants/example.caddy"
    validate_caddy
fi

printf '%s\n' 'OK: provisioning layout'
