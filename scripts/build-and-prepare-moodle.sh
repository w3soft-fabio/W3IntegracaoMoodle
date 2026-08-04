#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' "Usage: $0 <release-id> <moodle-git-ref>" >&2
    exit 2
fi

release_id="$1"
moodle_ref="$2"

case "$release_id" in
    *[!A-Za-z0-9._-]*|'')
        printf '%s\n' "Invalid release id." >&2
        exit 2
        ;;
esac

case "$moodle_ref" in
    *[!A-Za-z0-9._/-]*|'')
        printf '%s\n' "Invalid Moodle git ref." >&2
        exit 2
        ;;
esac

if ! printf '%s\n' "$moodle_ref" | grep -Eq '^([0-9a-fA-F]{40}|refs/tags/[A-Za-z0-9][A-Za-z0-9._/-]*)$'; then
    printf '%s\n' "Moodle ref must be a 40-character commit or an explicit refs/tags/... value." >&2
    exit 2
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
image="w3soft/moodle:$release_id"

cd "$project_root"
mkdir -p .provisioner generated/instituicoes proxy/tenants secrets

if docker image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "Image tag already exists and will not be overwritten: $image" >&2
    exit 1
fi

docker compose -f docker-compose.infra.yml config >/dev/null
docker compose -f docker-compose.infra.yml up -d
docker build --build-arg "MOODLE_REF=$moodle_ref" -t "$image" ./moodle
docker image inspect "$image" >/dev/null

temporary=".provisioner/current-image.tmp"
printf '%s\n' "$image" > "$temporary"
chmod 600 "$temporary"
mv "$temporary" .provisioner/current-image

printf '%s\n' "Prepared Moodle image: $image"
