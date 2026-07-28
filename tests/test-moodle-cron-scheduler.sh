#!/usr/bin/env bash

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCHEDULER="$ROOT/scripts/moodle-cron-scheduler.sh"
FAKE_DOCKER="$ROOT/tests/fixtures/fake-docker.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  output="$1"
  expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "saida nao contem: $expected"
}

label_output="$(
  FAKE_DOCKER_CONTAINERS="moodle_delta moodle_alpha moodle_charlie moodle_bravo moodle_echo" \
  MOODLE_CRON_DOCKER_BIN="$FAKE_DOCKER" \
    "$SCHEDULER" --dry-run
)"

assert_contains "$label_output" "tenant_count=5"
assert_contains "$label_output" "tenant=moodle_alpha offset_seconds=0"
assert_contains "$label_output" "tenant=moodle_bravo offset_seconds=15"
assert_contains "$label_output" "tenant=moodle_charlie offset_seconds=30"
assert_contains "$label_output" "tenant=moodle_delta offset_seconds=45"
assert_contains "$label_output" "tenant=moodle_echo offset_seconds=0"

two_output="$(
  FAKE_DOCKER_CONTAINERS="moodle_bravo moodle_alpha" \
  MOODLE_CRON_DOCKER_BIN="$FAKE_DOCKER" \
    "$SCHEDULER" --dry-run
)"

assert_contains "$two_output" "tenant=moodle_alpha offset_seconds=0"
assert_contains "$two_output" "tenant=moodle_bravo offset_seconds=30"

name_output="$(
  FAKE_DOCKER_CONTAINERS="moodle_proxy moodle_redis moodle_db moodle_escola_a moodle_escola_b moodle_escola_a_cron backup" \
  MOODLE_CRON_DISCOVERY_MODE=name \
  MOODLE_CRON_DOCKER_BIN="$FAKE_DOCKER" \
    "$SCHEDULER" --discover
)"

[[ "$name_output" == $'moodle_escola_a\nmoodle_escola_b' ]] ||
  fail "modo name selecionou containers incorretos: $name_output"

printf 'OK: scheduler discovery and balancing\n'
