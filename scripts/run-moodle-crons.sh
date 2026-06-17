#!/usr/bin/env sh

# Faz o script falhar se tentarmos ler uma variavel que nao foi definida.
# Em C#, pense nisso como evitar usar uma variavel local nao inicializada.
set -u

# O cron do sistema costuma rodar com PATH reduzido. Esta linha garante que
# comandos como docker, php, mkdir e sed possam ser encontrados.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Resolve a pasta raiz do projeto a partir da localizacao deste script.
# Assim o script funciona mesmo quando chamado pelo crontab.
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
LOCK_ROOT="${TMPDIR:-/tmp}/moodle-cron-locks"
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"

mkdir -p "$LOG_DIR"
mkdir -p "$LOCK_ROOT"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_line() {
  # Em shell, "$1" e "$2" sao os parametros recebidos pela funcao.
  tenant="$1"
  message="$2"

  # >> acrescenta no fim do arquivo. Se o arquivo nao existir, ele e criado.
  printf "[%s] %s\n" "$(timestamp)" "$message" >> "$LOG_DIR/$tenant.log"
}

load_default_tenants() {
  if [ ! -f "$TENANTS_FILE" ]; then
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2
    return 1
  fi

  # Remove comentarios e linhas vazias do arquivo de instituicoes.
  # A saida desta funcao vira a lista de containers a processar.
  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    "$TENANTS_FILE"
}

run_tenant_cron() {
  tenant="$1"
  lock_dir="$LOCK_ROOT/$tenant.lock"

  # >/dev/null descarta a saida normal.
  # 2>&1 manda a saida de erro para o mesmo destino da saida normal.
  if ! docker inspect "$tenant" >/dev/null 2>&1; then
    log_line "$tenant" "SKIP: container nao existe"
    return 0
  fi

  # Captura se o container esta rodando. Se o docker inspect falhar, assume false.
  running="$(docker inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null || printf "false")"

  if [ "$running" != "true" ]; then
    log_line "$tenant" "SKIP: container nao esta em execucao"
    return 0
  fi

  # mkdir e atomico: se a pasta ja existir, outro cron esta em andamento.
  # Isso funciona como um lock simples por instituicao.
  if ! mkdir "$lock_dir" 2>/dev/null; then
    log_line "$tenant" "SKIP: cron anterior ainda esta em execucao"
    return 0
  fi

  log_line "$tenant" "START: executando cron"

  # Executa o cron dentro do container como www-data.
  # Toda a saida do Moodle e anexada ao log da instituicao.
  docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php >> "$LOG_DIR/$tenant.log" 2>&1

  # "$?" e o codigo de saida do ultimo comando executado.
  # Zero significa sucesso; qualquer outro valor indica erro.
  status="$?"

  if [ "$status" -eq 0 ]; then
    log_line "$tenant" "OK: cron finalizado com sucesso"
  else
    log_line "$tenant" "ERROR: cron finalizado com status $status"
  fi

  rmdir "$lock_dir" 2>/dev/null || true

  # Retorna para quem chamou a funcao o mesmo status do cron do Moodle.
  return "$status"
}

# "$#" e a quantidade de argumentos recebidos pelo script.
# Se nenhum container foi informado na linha de comando, carregamos a lista padrao.
if [ "$#" -eq 0 ]; then
  tenants="$(load_default_tenants)" || exit 1

  # set -- substitui os argumentos atuais do script.
  # Depois desta linha, "$@" passa a representar as instituicoes do arquivo.
  set -- $tenants
fi

FINAL_STATUS=0

# "$@" representa todos os argumentos, preservando cada item como um argumento.
for tenant in "$@"; do
  run_tenant_cron "$tenant" || FINAL_STATUS=1
done

# O codigo de saida final permite que o crontab/shell saiba se houve erro.
exit "$FINAL_STATUS"
