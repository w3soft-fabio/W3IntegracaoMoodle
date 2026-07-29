#!/usr/bin/env bash

# Este script e interpretado pelo Bash (nao compilado como C#). O "shebang"
# acima informa qual interpretador deve executa-lo. As configuracoes abaixo
# fazem o Bash se comportar de maneira menos permissiva, aproximando-o da
# previsibilidade esperada em uma aplicacao tipada.
set -uo pipefail

# `PATH` e a lista de diretorios onde o sistema procura executaveis como
# `docker`, `awk` e `flock`. Definimos os diretorios usuais explicitamente
# para o cron nao depender do PATH reduzido que servicos normalmente recebem.
# `${PATH:-}` significa: use a variavel PATH atual; se ela nao existir, use
# uma string vazia. E o equivalente conceitual a um valor default em C#.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Variaveis de ambiente permitem configurar o programa sem alterar o arquivo.
# A expressao `${NOME:-padrao}` corresponde aproximadamente a
# `Environment.GetEnvironmentVariable("NOME") ?? "padrao"` em C# (e tambem
# usa o padrao quando a variavel esta vazia).
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

# Funcoes em Bash sao blocos reutilizaveis, semelhantes a metodos sem tipo de
# retorno declarado. O status retornado e um codigo inteiro: 0 indica sucesso
# e qualquer outro valor indica falha, como ExitCode de um Process em .NET.
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
  # Argumentos de funcao sao acessados por posicao: $1 e o primeiro, $2 o
  # segundo e assim por diante. `shift` remove o primeiro argumento; depois
  # disso, `$*` reune todos os argumentos restantes como uma unica mensagem.
  level="$1"
  shift
  printf 'level=%s timestamp=%s %s\n' "$level" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

die() {
  # Centraliza erros fatais: registra a causa e encerra o processo com codigo 1.
  log error "message=\"$*\""
  exit 1
}

validate_non_negative_integer() {
  name="$1"
  value="$2"
  # `[[ ... ]]` e a forma segura de testar condicoes no Bash. `=~` compara
  # contra uma expressao regular; `||` executa a proxima instrucao apenas se o
  # teste falhar. Portanto, isto equivale a validar com Regex em C# e lancar
  # uma excecao se o valor nao for composto apenas por digitos.
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name deve ser um inteiro nao negativo"
}

validate_positive_integer() {
  name="$1"
  value="$2"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$name deve ser um inteiro positivo"
}

discover_by_label() {
  # A descoberta por label delega ao Docker o filtro. `--format` seleciona
  # apenas o nome de cada container, produzindo uma linha por resultado.
  "$DOCKER_BIN" ps \
    --filter status=running \
    --filter "label=$TENANT_LABEL" \
    --format '{{.Names}}'
}

discover_by_name() {
  # Alternativa para ambientes sem labels: o `awk` recebe cada nome de
  # container e aplica regras de inclusao/exclusao. Pense nele como um pequeno
  # `foreach` com varios `if`s que escreve (`print`) somente os nomes aceitos.
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
  # `case` e o equivalente mais proximo de um `switch` em C#.
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
  # O resultado do `case` e enviado por pipe (`|`) ao `sort -u`: ordena e
  # remove duplicados. `LC_ALL=C` torna a ordenacao deterministica, sem variar
  # conforme o idioma/configuracao regional da maquina.
  esac | LC_ALL=C sort -u
}

container_is_eligible() {
  tenant="$1"
  # `$(...)` captura a saida de um comando, semelhantemente a atribuir o
  # resultado de uma chamada a uma variavel. `2>/dev/null` descarta mensagens
  # de erro do Docker. Se `inspect` falhar, `|| return 1` encerra esta funcao
  # indicando que o container nao e elegivel, sem encerrar o scheduler todo.
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

  # O lock de capacidade funciona como um `SemaphoreSlim(MAX_PARALLEL)`, mas
  # e compartilhado entre processos. Cada arquivo `capacity-N.lock` representa
  # uma permissao. O loop tenta obter uma permissao ate o prazo de fila.
  while (( $(date +%s) < deadline_epoch )); do
    for ((slot_number = 1; slot_number <= MAX_PARALLEL; slot_number++)); do
      # `exec {candidate_fd}>arquivo` abre o arquivo e guarda o numero do
      # descritor em `candidate_fd`. Um descritor e um identificador de arquivo
      # aberto, parecido com um handle de recurso do sistema em C#.
      if flock -n "$candidate_fd"; then
        acquired_slot_fd="$candidate_fd"
        acquired_slot_number="$slot_number"
        return 0
      fi
      # Nao conseguimos o lock deste slot; fechamos imediatamente o descritor
      # para nao acumular handles abertos a cada tentativa.
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

  # Primeiro obtemos um lock exclusivo por tenant. Isso impede duas execucoes
  # simultaneas do cron para o mesmo Moodle, mesmo que haja mais de um ciclo
  # tentando agenda-lo. O lock permanece enquanto este processo filho viver.
  exec {tenant_fd}>"$LOCK_DIR/tenant-$tenant.lock"
  if ! flock -n "$tenant_fd"; then
    log warning "event=cron_skip tenant=$tenant reason=previous_execution_running"
    return 0
  fi

  # Depois do lock individual, adquirimos uma vaga global. A ordem e
  # importante: quem ja esta executando um tenant nao deve disputar a fila por
  # capacidade. A vaga fica retida pelo descritor `acquired_slot_fd` ate esta
  # funcao terminar, quando o Bash fecha automaticamente seus descritores.
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

  # Arrays preservam cada argumento separadamente. Isso evita problemas de
  # espacos e escaping que ocorreriam ao montar uma unica string de comando.
  # `${command[@]}` abaixo e análogo a passar uma lista de argumentos para
  # `ProcessStartInfo.ArgumentList` em vez de concatenar CommandLine.
  command=(
    "$DOCKER_BIN" exec -u www-data "$tenant"
    php /var/www/html/admin/cli/cron.php --keep-alive=0
  )

  # Se configurado, `timeout` envia TERM ao processo que ultrapassar o limite
  # e, apos 30 segundos adicionais, forca seu encerramento. Sem limite (0),
  # executamos o array diretamente.
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

  # `${#WINDOW_OFFSETS[@]}` e o tamanho do array (4). Com menos de quatro
  # tenants, a formula os espalha pelas quatro janelas. Com quatro ou mais,
  # modulo (`%`) distribui em rodizio: 0, 1, 2, 3, 0, 1... .
  if (( tenant_count < ${#WINDOW_OFFSETS[@]} )); then
    printf '%s\n' $((tenant_index * ${#WINDOW_OFFSETS[@]} / tenant_count))
  else
    printf '%s\n' $((tenant_index % ${#WINDOW_OFFSETS[@]}))
  fi
}

load_tenants() {
  # Capturamos a lista descoberta antes de preencher o array. O bloco apos
  # `||` so roda quando a descoberta falha; e equivalente a um tratamento de
  # erro local que devolve falha para quem chamou esta funcao.
  discovered_tenants="$(discover_tenants)" || {
    log error "event=discovery_failure mode=$DISCOVERY_MODE"
    return 1
  }

  tenants=()
  # `read -r` le uma linha por vez sem interpretar barras invertidas. `IFS=`
  # impede que espacos nas extremidades sejam removidos. `<<<` e um here-string:
  # fornece o conteudo da variavel como entrada para o `while`.
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
  # Nao usamos apenas `sleep 15`: calculamos o horario absoluto desejado. Isso
  # evita que o tempo gasto nas etapas anteriores acumule atraso a cada janela.
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

    # Esta sintaxe de `for ((...))` e deliberadamente parecida com C#:
    # `for (var tenantIndex = 0; tenantIndex < tenantCount; tenantIndex++)`.
    # O `&` no fim inicia a funcao em processo filho, permitindo que tenants da
    # mesma janela comecem em paralelo; `MAX_PARALLEL` ainda limita quantos
    # deles efetivamente executam o cron ao mesmo tempo.
    for ((tenant_index = 0; tenant_index < tenant_count; tenant_index++)); do
      assigned_slot="$(slot_for_tenant "$tenant_index" "$tenant_count")"
      if (( assigned_slot == slot_index )); then
        run_tenant_cron "${tenants[$tenant_index]}" "$scheduled_epoch" &
      fi
    done
  done
}

next_minute_epoch() {
  # Epoch e o numero de segundos desde 1970-01-01 UTC. A conta arredonda o
  # instante atual para cima ate o proximo multiplo de 60, isto e, o proximo
  # inicio de minuto. `printf`, em vez de `echo`, fornece saida previsivel.
  now_epoch="$(date +%s)"
  printf '%s\n' $((((now_epoch / 60) + 1) * 60))
}

# `$#` e a quantidade de argumentos recebidos pelo script. Este laço consome
# cada opcao da linha de comando, como um parser simples de argumentos.
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
# O label precisa ter a forma `chave=valor`, porque antes o script separou as
# duas partes com expansoes de string do Bash (`%%=*` e `#*=`).
if [[ "$TENANT_LABEL" != *=* || -z "$TENANT_LABEL_KEY" || -z "$TENANT_LABEL_VALUE" ]]; then
  die "MOODLE_CRON_TENANT_LABEL deve usar o formato chave=valor"
fi

# `command -v` verifica se um executavel pode ser localizado no PATH. Toda a
# saida e redirecionada para /dev/null porque so importa o codigo de sucesso.
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
# O descritor 9 e reservado para o lock da instancia inteira do scheduler. Um
# segundo processo tentara bloquear o mesmo arquivo e falhara imediatamente,
# evitando dois schedulers concorrentes no mesmo host.
exec 9>"$LOCK_DIR/scheduler.lock"
flock -n 9 || die "outra instancia do scheduler ja esta ativa"

# `trap` registra o equivalente a um manipulador de sinal: TERM (encerramento
# solicitado pelo servico) ou INT (Ctrl+C). O log torna a parada observavel.
trap 'log info "event=scheduler_stop"; exit 0' TERM INT

if [[ "$MODE" == "once" ]]; then
  run_cycle "$(next_minute_epoch)"
  # `wait` aguarda todos os processos filhos criados com `&`, como aguardar um
  # conjunto de Tasks antes de finalizar a aplicacao de linha de comando.
  wait
  exit $?
fi

log info "event=scheduler_start discovery_mode=$DISCOVERY_MODE max_parallel=$MAX_PARALLEL queue_timeout_seconds=$QUEUE_TIMEOUT_SECONDS"

while true; do
  # No modo daemon, cada iteracao prepara o proximo minuto, espera ate ele e
  # entao agenda as janelas de 0, 15, 30 e 45 segundos desse minuto.
  cycle_epoch="$(next_minute_epoch)"
  sleep_until "$cycle_epoch"
  run_cycle "$cycle_epoch"
done
