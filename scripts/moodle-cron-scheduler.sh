#!/usr/bin/env bash

set -uo pipefail

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

DOCKER_BIN="${MOODLE_CRON_DOCKER_BIN:-docker}"
DISCOVERY_MODE="${MOODLE_CRON_DISCOVERY_MODE:-label}"
TENANT_LABEL="${MOODLE_CRON_TENANT_LABEL:-com.w3soft.moodle.role=tenant}"
TENANT_LABEL_KEY="${TENANT_LABEL%%=*}"
TENANT_LABEL_VALUE="${TENANT_LABEL#*=}"
LOCK_DIR="${MOODLE_CRON_LOCK_DIR:-/run/moodle-cron-scheduler}"
MAX_PARALLEL="${MOODLE_CRON_MAX_PARALLEL:-2}"
QUEUE_TIMEOUT_SECONDS="${MOODLE_CRON_QUEUE_TIMEOUT_SECONDS:-50}"
COMMAND_TIMEOUT_SECONDS="${MOODLE_CRON_COMMAND_TIMEOUT_SECONDS:-0}"
SLOW_WARNING_SECONDS="${MOODLE_CRON_SLOW_WARNING_SECONDS:-60}"
WINDOW_OFFSETS=(0 15 30 45)
MODE="daemon"

usage() {
  printf '%s\n' \
    "Uso: $0 [--daemon|--once|--dry-run|--discover]" \
    "" \
    "  --daemon     Executa continuamente (padrao)." \
    "  --once       Agenda um unico ciclo nas janelas do proximo minuto." \
    "  --dry-run    Mostra o balanceamento sem executar o cron." \
    "  --discover   Imprime somente os containers elegiveis."
}

log() {
  level="$1"
  shift
  printf 'level=%s timestamp=%s %s\n' "$level" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

die() {
  log error "message=\"$*\""
  exit 1
}

validate_non_negative_integer() {
  name="$1"
  value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name deve ser um inteiro nao negativo"
}

validate_positive_integer() {
  name="$1"
  value="$2"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name deve ser um inteiro positivo"
}

discover_by_label() {
  "$DOCKER_BIN" ps \
    --filter status=running \
    --filter "label=$TENANT_LABEL" \
    --format '{{.Names}}'
}

discover_by_name() {
  "$DOCKER_BIN" ps --filter status=running --format '{{.Names}}' |
    awk '
      /^moodle_/ &&
      $0 != "moodle_proxy" &&
      $0 != "moodle_redis" &&
      $0 != "moodle_db" &&
      $0 !~ /_cron$/ {
        print
      }
    '
}

discover_tenants() {
  case "$DISCOVERY_MODE" in
    label)
      discover_by_label
      ;;
    name)
      discover_by_name
      ;;
    *)
      die "MOODLE_CRON_DISCOVERY_MODE deve ser label ou name"
      ;;
  esac | LC_ALL=C sort -u
}

container_is_eligible() {
  tenant="$1"
  running="$("$DOCKER_BIN" inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null)" || return 1
  [[ "$running" == "true" ]] || return 1

  if [[ "$DISCOVERY_MODE" == "label" ]]; then
    role="$("$DOCKER_BIN" inspect \
      --format "{{ index .Config.Labels \"$TENANT_LABEL_KEY\" }}" \
      "$tenant" 2>/dev/null)" || return 1
    [[ "$role" == "$TENANT_LABEL_VALUE" ]] || return 1
  fi
}

acquire_capacity_slot() {
  deadline_epoch="$1"
  acquired_slot_fd=""
  acquired_slot_number=""

  while (( $(date +%s) < deadline_epoch )); do
    for ((slot_number = 1; slot_number <= MAX_PARALLEL; slot_number++)); do
      exec {candidate_fd}>"$LOCK_DIR/capacity-$slot_number.lock"
      if flock -n "$candidate_fd"; then
        acquired_slot_fd="$candidate_fd"
        acquired_slot_number="$slot_number"
        return 0
      fi
      exec {candidate_fd}>&-
    done
    sleep 1
  done

  return 1
}

run_tenant_cron() {
  tenant="$1"
  scheduled_epoch="$2"
  deadline_epoch=$((scheduled_epoch + QUEUE_TIMEOUT_SECONDS))

  exec {tenant_fd}>"$LOCK_DIR/tenant-$tenant.lock"
  if ! flock -n "$tenant_fd"; then
    log warning "event=cron_skip tenant=$tenant reason=previous_execution_running"
    return 0
  fi

  if ! acquire_capacity_slot "$deadline_epoch"; then
    log warning "event=cron_skip tenant=$tenant reason=capacity_timeout timeout_seconds=$QUEUE_TIMEOUT_SECONDS"
    return 0
  fi

  if ! container_is_eligible "$tenant"; then
    log warning "event=cron_skip tenant=$tenant reason=container_not_eligible"
    return 0
  fi

  started_epoch="$(date +%s)"
  log info "event=cron_start tenant=$tenant capacity_slot=$acquired_slot_number"

  command=(
    "$DOCKER_BIN" exec -u www-data "$tenant"
    php /var/www/html/admin/cli/cron.php --keep-alive=0
  )

  if (( COMMAND_TIMEOUT_SECONDS > 0 )); then
    timeout --signal=TERM --kill-after=30 \
      "$COMMAND_TIMEOUT_SECONDS" "${command[@]}"
  else
    "${command[@]}"
  fi
  status=$?

  finished_epoch="$(date +%s)"
  duration=$((finished_epoch - started_epoch))

  if (( status == 0 )); then
    level=info
    result=success
  else
    level=error
    result=failure
  fi

  log "$level" "event=cron_finish tenant=$tenant result=$result status=$status duration_seconds=$duration"

  if (( duration > SLOW_WARNING_SECONDS )); then
    log warning "event=cron_slow tenant=$tenant duration_seconds=$duration threshold_seconds=$SLOW_WARNING_SECONDS"
  fi

  return "$status"
}

slot_for_tenant() {
  tenant_index="$1"
  tenant_count="$2"

  if (( tenant_count < ${#WINDOW_OFFSETS[@]} )); then
    printf '%s\n' $((tenant_index * ${#WINDOW_OFFSETS[@]} / tenant_count))
  else
    printf '%s\n' $((tenant_index % ${#WINDOW_OFFSETS[@]}))
  fi
}

load_tenants() {
  discovered_tenants="$(discover_tenants)" || {
    log error "event=discovery_failure mode=$DISCOVERY_MODE"
    return 1
  }

  tenants=()
  while IFS= read -r tenant; do
    if [[ -n "$tenant" ]]; then
      tenants+=("$tenant")
    fi
  done <<< "$discovered_tenants"
}

print_distribution() {
  tenant_count="${#tenants[@]}"

  log info "event=discovery tenant_count=$tenant_count mode=$DISCOVERY_MODE"
  if (( tenant_count == 0 )); then
    return 0
  fi

  for ((tenant_index = 0; tenant_index < tenant_count; tenant_index++)); do
    slot_index="$(slot_for_tenant "$tenant_index" "$tenant_count")"
    log info "event=assignment tenant=${tenants[$tenant_index]} offset_seconds=${WINDOW_OFFSETS[$slot_index]}"
  done
}

sleep_until() {
  target_epoch="$1"
  now_epoch="$(date +%s)"
  delay=$((target_epoch - now_epoch))
  if (( delay > 0 )); then
    sleep "$delay"
  fi
}

run_cycle() {
  base_epoch="$1"
  load_tenants || return 1
  tenant_count="${#tenants[@]}"

  print_distribution
  if (( tenant_count == 0 )); then
    return 0
  fi

  for ((slot_index = 0; slot_index < ${#WINDOW_OFFSETS[@]}; slot_index++)); do
    scheduled_epoch=$((base_epoch + WINDOW_OFFSETS[slot_index]))
    sleep_until "$scheduled_epoch"

    for ((tenant_index = 0; tenant_index < tenant_count; tenant_index++)); do
      assigned_slot="$(slot_for_tenant "$tenant_index" "$tenant_count")"
      if (( assigned_slot == slot_index )); then
        run_tenant_cron "${tenants[$tenant_index]}" "$scheduled_epoch" &
      fi
    done
  done
}

next_minute_epoch() {
  now_epoch="$(date +%s)"
  printf '%s\n' $((((now_epoch / 60) + 1) * 60))
}

while (( $# > 0 )); do
  case "$1" in
    --daemon) MODE="daemon" ;;
    --once) MODE="once" ;;
    --dry-run) MODE="dry-run" ;;
    --discover) MODE="discover" ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

validate_positive_integer MOODLE_CRON_MAX_PARALLEL "$MAX_PARALLEL"
validate_positive_integer MOODLE_CRON_QUEUE_TIMEOUT_SECONDS "$QUEUE_TIMEOUT_SECONDS"
validate_non_negative_integer MOODLE_CRON_COMMAND_TIMEOUT_SECONDS "$COMMAND_TIMEOUT_SECONDS"
validate_non_negative_integer MOODLE_CRON_SLOW_WARNING_SECONDS "$SLOW_WARNING_SECONDS"
if [[ "$TENANT_LABEL" != *=* || -z "$TENANT_LABEL_KEY" || -z "$TENANT_LABEL_VALUE" ]]; then
  die "MOODLE_CRON_TENANT_LABEL deve usar o formato chave=valor"
fi

command -v "$DOCKER_BIN" >/dev/null 2>&1 || die "comando Docker nao encontrado: $DOCKER_BIN"

if [[ "$MODE" == "discover" ]]; then
  discover_tenants
  exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
  load_tenants || exit 1
  print_distribution
  exit 0
fi

command -v flock >/dev/null 2>&1 || die "comando flock nao encontrado"
if (( COMMAND_TIMEOUT_SECONDS > 0 )); then
  command -v timeout >/dev/null 2>&1 || die "comando timeout nao encontrado"
fi

mkdir -p "$LOCK_DIR"
exec 9>"$LOCK_DIR/scheduler.lock"
flock -n 9 || die "outra instancia do scheduler ja esta ativa"

trap 'log info "event=scheduler_stop"; exit 0' TERM INT

if [[ "$MODE" == "once" ]]; then
  run_cycle "$(next_minute_epoch)"
  wait
  exit $?
fi

log info "event=scheduler_start discovery_mode=$DISCOVERY_MODE max_parallel=$MAX_PARALLEL queue_timeout_seconds=$QUEUE_TIMEOUT_SECONDS"

while true; do
  cycle_epoch="$(next_minute_epoch)"
  sleep_until "$cycle_epoch"
  run_cycle "$cycle_epoch"
done
