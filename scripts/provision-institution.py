#!/usr/bin/env python3

import argparse
import json
import re
import secrets
import string
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPOSE_FILE = ROOT / "docker-compose.instituicoes.yml"
CADDY_FILE = ROOT / "proxy" / "Caddyfile.local"
CRON_TENANTS_FILE = ROOT / "config" / "moodle-cron-tenants.txt"
SECRETS_DIR = ROOT / "secrets"
IMAGE_TAG = "w3soft/moodle:2026.06.1-local"


REQUIRED_FIELDS = [
    "displayName",
    "slug",
    "tenantId",
    "databasePassword",
    "publicUrl",
    "cpu",
    "memoryLimit",
    "memoryReservation",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def load_spec(path: Path) -> dict:
    if not path.exists():
        fail(f"JSON file not found: {path}")

    try:
        data = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON in {path}: {exc}")

    for field in REQUIRED_FIELDS:
        if field not in data or data[field] in ("", None):
            fail(f"Missing required field in JSON: {field}")

    slug = data["slug"]
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*[a-z0-9]", slug):
        fail("slug must use lowercase letters, numbers and hyphens, and cannot start or end with hyphen")

    return data


def slug_to_identifier(slug: str) -> str:
    return slug.replace("-", "_")


def caddy_matcher(slug: str) -> str:
    return "@tenant" + re.sub(r"[^a-z0-9]", "", slug)


def random_password() -> str:
    # Moodle's default policy requires letters, digits and a non-alphanumeric char.
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(28)) + "!7"


def parse_env(path: Path) -> dict:
    values = {}
    if not path.exists():
        return values

    for raw_line in read_text(path).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        values[key] = value
    return values


def env_lines(values: dict) -> str:
    groups = [
        [
            "MOODLE_URL",
            "MOODLE_DB_HOST",
            "MOODLE_DB_NAME",
            "MOODLE_DB_USER",
            "MOODLE_DB_PASSWORD",
            "MOODLE_DATAROOT",
            "MOODLE_PUBLIC_SLUG",
            "MOODLE_TENANT_ID",
            "MOODLE_REDIS_HOST",
            "MOODLE_REDIS_PORT",
            "MOODLE_REDIS_PREFIX",
        ],
        [
            "MOODLE_AUTO_BOOTSTRAP",
            "MOODLE_SITE_FULLNAME",
            "MOODLE_SITE_SHORTNAME",
            "MOODLE_SITE_SUMMARY",
            "MOODLE_SUPPORT_EMAIL",
        ],
        [
            "MOODLE_ADMIN_USER",
            "MOODLE_ADMIN_PASSWORD",
            "MOODLE_ADMIN_FIRSTNAME",
            "MOODLE_ADMIN_LASTNAME",
            "MOODLE_ADMIN_EMAIL",
            "MOODLE_ADMIN_CITY",
            "MOODLE_ADMIN_COUNTRY",
            "MOODLE_ADMIN_TIMEZONE",
            "MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL",
        ],
        [
            "MOODLE_WS_SERVICE_NAME",
            "MOODLE_WS_SERVICE_SHORTNAME",
            "MOODLE_WS_FUNCTIONS",
            "MOODLE_WS_USER_USERNAME",
            "MOODLE_WS_USER_PASSWORD",
            "MOODLE_WS_USER_FIRSTNAME",
            "MOODLE_WS_USER_LASTNAME",
            "MOODLE_WS_USER_EMAIL",
            "MOODLE_WS_USER_CITY",
            "MOODLE_WS_USER_COUNTRY",
            "MOODLE_WS_USER_TIMEZONE",
            "MOODLE_WS_ROLE_SHORTNAME",
            "MOODLE_WS_TOKEN_FILE",
            "MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME",
        ],
    ]

    rendered = []
    for group in groups:
        if rendered:
            rendered.append("")
        rendered.extend(f"{key}={values[key]}" for key in group)
    return "\n".join(rendered) + "\n"


def default_env(spec: dict) -> dict:
    slug = spec["slug"]
    ident = slug_to_identifier(slug)
    db_name = f"moodle_{ident}"
    local_email_domain = f"{slug}.local"

    return {
        "MOODLE_URL": spec["publicUrl"],
        "MOODLE_DB_HOST": "db",
        "MOODLE_DB_NAME": db_name,
        "MOODLE_DB_USER": db_name,
        "MOODLE_DB_PASSWORD": spec["databasePassword"],
        "MOODLE_DATAROOT": "/var/www/moodledata",
        "MOODLE_PUBLIC_SLUG": slug,
        "MOODLE_TENANT_ID": spec["tenantId"],
        "MOODLE_REDIS_HOST": "redis",
        "MOODLE_REDIS_PORT": "6379",
        "MOODLE_REDIS_PREFIX": f"{ident}_",
        "MOODLE_AUTO_BOOTSTRAP": "1",
        "MOODLE_SITE_FULLNAME": spec["displayName"],
        "MOODLE_SITE_SHORTNAME": slug,
        "MOODLE_SITE_SUMMARY": "",
        "MOODLE_SUPPORT_EMAIL": f"suporte@{local_email_domain}",
        "MOODLE_ADMIN_USER": "admin",
        "MOODLE_ADMIN_PASSWORD": random_password(),
        "MOODLE_ADMIN_FIRSTNAME": "Administrador",
        "MOODLE_ADMIN_LASTNAME": "Principal",
        "MOODLE_ADMIN_EMAIL": f"admin@{local_email_domain}",
        "MOODLE_ADMIN_CITY": "Maceio",
        "MOODLE_ADMIN_COUNTRY": "BR",
        "MOODLE_ADMIN_TIMEZONE": "America/Maceio",
        "MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL": "1",
        "MOODLE_WS_SERVICE_NAME": "W3Soft Student Sync",
        "MOODLE_WS_SERVICE_SHORTNAME": "w3soft_student_sync",
        "MOODLE_WS_FUNCTIONS": (
            "core_webservice_get_site_info,core_course_get_courses,"
            "core_course_get_courses_by_field,core_user_get_users_by_field,"
            "core_user_create_users,enrol_manual_enrol_users"
        ),
        "MOODLE_WS_USER_USERNAME": "svc_integracao",
        "MOODLE_WS_USER_PASSWORD": random_password(),
        "MOODLE_WS_USER_FIRSTNAME": "Servico",
        "MOODLE_WS_USER_LASTNAME": "Integracao",
        "MOODLE_WS_USER_EMAIL": f"svc_integracao@{local_email_domain}",
        "MOODLE_WS_USER_CITY": "Maceio",
        "MOODLE_WS_USER_COUNTRY": "BR",
        "MOODLE_WS_USER_TIMEZONE": "America/Maceio",
        "MOODLE_WS_ROLE_SHORTNAME": "w3soft_ws_integration",
        "MOODLE_WS_TOKEN_FILE": "/var/www/moodledata/w3soft/ws-token.txt",
        "MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME": "student",
    }


def upsert_env_file(spec: dict, dry_run: bool) -> Path:
    path = SECRETS_DIR / f"{spec['slug']}.local.env"
    defaults = default_env(spec)
    existing = parse_env(path)
    merged = {**defaults, **existing}
    content = env_lines(merged)

    if dry_run:
        print(f"DRY-RUN: would write {path.relative_to(ROOT)}")
        return path

    SECRETS_DIR.mkdir(exist_ok=True)
    write_text(path, content)
    path.chmod(0o600)
    return path


def upsert_compose(spec: dict, dry_run: bool) -> None:
    content = read_text(COMPOSE_FILE)
    ident = slug_to_identifier(spec["slug"])
    service = f"moodle_{ident}"
    volume = f"moodledata_{ident}"

    if f"  {service}:" not in content:
        block = f"""  {service}:
    image: {IMAGE_TAG}
    container_name: {service}
    restart: unless-stopped
    env_file:
      - ./secrets/{spec['slug']}.local.env
    volumes:
      - {volume}:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "{spec['cpu']}"
    mem_limit: {spec['memoryLimit']}
    mem_reservation: {spec['memoryReservation']}
"""
        content = content.replace("\nvolumes:\n", "\n" + block + "volumes:\n")

    if f"  {volume}:" not in content:
        block = f"""  {volume}:
    name: {volume}
"""
        content = content.replace("\nnetworks:\n", "\n" + block + "networks:\n")

    if dry_run:
        print(f"DRY-RUN: would update {COMPOSE_FILE.relative_to(ROOT)}")
    else:
        write_text(COMPOSE_FILE, content)


def upsert_caddy(spec: dict, dry_run: bool) -> None:
    content = read_text(CADDY_FILE)
    slug = spec["slug"]
    service = f"moodle_{slug_to_identifier(slug)}"
    matcher = caddy_matcher(slug)

    if f"{matcher} path /i/{slug}/*" not in content:
        content = content.replace("\n\tredir @home /index.html", f"\n\t{matcher} path /i/{slug}/*\n\tredir @home /index.html")

    if f"\tredir /i/{slug} /i/{slug}/" not in content:
        content = content.replace("\n\thandle @index {", f"\n\tredir /i/{slug} /i/{slug}/\n\thandle @index {{")

    if f"handle {matcher}" not in content:
        handle = f"""
	handle {matcher} {{
		reverse_proxy {service}:80
	}}
"""
        content = content.replace("\n\trespond \"Proxy local da infraestrutura Moodle funcionando\" 200", handle + "\n\trespond \"Proxy local da infraestrutura Moodle funcionando\" 200")

    if dry_run:
        print(f"DRY-RUN: would update {CADDY_FILE.relative_to(ROOT)}")
    else:
        write_text(CADDY_FILE, content)


def upsert_cron_tenant(spec: dict, dry_run: bool) -> None:
    service = f"moodle_{slug_to_identifier(spec['slug'])}"
    content = read_text(CRON_TENANTS_FILE)
    lines = content.splitlines()

    if service not in lines:
        if content and not content.endswith("\n"):
            content += "\n"
        content += service + "\n"

    if dry_run:
        print(f"DRY-RUN: would update {CRON_TENANTS_FILE.relative_to(ROOT)}")
    else:
        write_text(CRON_TENANTS_FILE, content)


def sql_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def run_command(command: list, dry_run: bool, stdin: str = None, dry_run_label: str = None) -> None:
    printable = " ".join(command)
    if dry_run:
        print(f"DRY-RUN: would run {dry_run_label or printable}")
        return
    subprocess.run(command, cwd=ROOT, input=stdin, text=True, check=True)


def create_database(spec: dict, dry_run: bool) -> None:
    ident = slug_to_identifier(spec["slug"])
    db_name = f"moodle_{ident}"
    password = sql_escape(spec["databasePassword"])
    sql = (
        f"CREATE DATABASE IF NOT EXISTS {db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; "
        f"CREATE USER IF NOT EXISTS '{db_name}'@'%' IDENTIFIED BY '{password}'; "
        f"ALTER USER '{db_name}'@'%' IDENTIFIED BY '{password}'; "
        f"GRANT ALL PRIVILEGES ON {db_name}.* TO '{db_name}'@'%'; "
        "FLUSH PRIVILEGES;"
    )
    run_command(
        [
            "docker",
            "exec",
            "-i",
            "moodle_db",
            "sh",
            "-c",
            "mariadb --ssl=0 -uroot -p\"$MARIADB_ROOT_PASSWORD\"",
        ],
        dry_run,
        stdin=sql,
        dry_run_label=f"docker exec -i moodle_db sh -c 'mariadb --ssl=0 -uroot -p\"$MARIADB_ROOT_PASSWORD\"' < SQL for {db_name}",
    )


def rebuild_image(dry_run: bool) -> None:
    run_command(["docker", "build", "-t", IMAGE_TAG, "./moodle"], dry_run)


def start_tenant(spec: dict, dry_run: bool) -> None:
    service = f"moodle_{slug_to_identifier(spec['slug'])}"
    run_command(["docker", "compose", "-f", "docker-compose.instituicoes.yml", "up", "-d", service], dry_run)
    run_command(["docker", "compose", "-f", "docker-compose.infra.yml", "restart", "proxy"], dry_run)


def main() -> None:
    parser = argparse.ArgumentParser(description="Provision a Moodle institution from a JSON spec.")
    parser.add_argument("json_file", type=Path)
    parser.add_argument("--create-db", action="store_true", help="Create/update the tenant database and user in moodle_db.")
    parser.add_argument("--rebuild-image", action="store_true", help=f"Rebuild {IMAGE_TAG}.")
    parser.add_argument("--up", action="store_true", help="Start the tenant container and restart the proxy.")
    parser.add_argument("--apply-all", action="store_true", help="Run file updates, DB creation, image rebuild and container start.")
    parser.add_argument("--dry-run", action="store_true", help="Print planned actions without writing files or running Docker commands.")
    args = parser.parse_args()

    spec = load_spec(args.json_file)
    upsert_compose(spec, args.dry_run)
    upsert_caddy(spec, args.dry_run)
    upsert_cron_tenant(spec, args.dry_run)
    env_path = upsert_env_file(spec, args.dry_run)

    if args.create_db or args.apply_all:
        create_database(spec, args.dry_run)
    if args.rebuild_image or args.apply_all:
        rebuild_image(args.dry_run)
    if args.up or args.apply_all:
        start_tenant(spec, args.dry_run)

    print(f"Tenant prepared: {spec['displayName']} ({spec['slug']})")
    print(f"Secret file: {env_path.relative_to(ROOT)}")
    print("Sensitive values were written only to the secret file.")


if __name__ == "__main__":
    main()
