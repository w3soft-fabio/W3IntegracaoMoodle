#!/usr/bin/env sh

# Faz o script falhar se tentarmos ler uma variavel que nao foi definida.
set -u

# O cron do sistema costuma ter PATH reduzido. Incluimos os caminhos comuns
# para o shell encontrar docker, sed, sleep e os demais comandos.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Resolve a pasta raiz do projeto a partir da localizacao deste script.
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"
RUNNER="$PROJECT_DIR/scripts/run-moodle-crons.sh"
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
DISTRIBUTOR_LOG="$LOG_DIR/distributor.log"

# O minuto sera dividido em 4 janelas fixas: 00s, 15s, 30s e 45s.
# A quantidade de instituicoes por janela e calculada dinamicamente.
WINDOW_COUNT=4
WINDOW_STEP_SECONDS=15

# Guarda os IDs dos processos iniciados em background.
PIDS=""

mkdir -p "$LOG_DIR"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_distributor() {
  # "$1" e a mensagem recebida pela funcao.
  printf "[%s] %s\n" "$(timestamp)" "$1" >> "$DISTRIBUTOR_LOG"
}

load_tenants() {
  if [ ! -f "$TENANTS_FILE" ]; then
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2
    return 1
  fi

  # Remove comentarios e linhas vazias do arquivo de instituicoes.
  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    "$TENANTS_FILE"
}

run_group() {
  # Primeiro argumento: quantos segundos esperar antes de executar o grupo.
  delay="$1"

  # shift descarta o primeiro argumento.
  # Depois disso, "$@" contem somente os containers do grupo.
  shift

  if [ "$#" -eq 0 ]; then
    return 0
  fi

  log_distributor "SCHEDULE: delay ${delay}s: $*"

  # Os parenteses criam um subshell.
  # O & no final inicia esse bloco em background, permitindo agendar
  # os grupos de 00s, 15s, 30s e 45s sem bloquear o script principal.
  (
    sleep "$delay"
    "$RUNNER" "$@"
  ) &

  # "$!" e o PID do ultimo processo iniciado em background.
  # Guardamos para esperar todos terminarem no fim do script.
  PIDS="$PIDS $!"
}

tenants="$(load_tenants)" || exit 1

# set -- substitui os argumentos atuais do script pela lista de instituicoes.
# A partir daqui, "$@" representa os containers lidos do arquivo.
set -- $tenants

# "$#" e a quantidade de argumentos atuais, ou seja, de instituicoes carregadas.
if [ "$#" -eq 0 ]; then
  log_distributor "SKIP: nenhuma instituicao configurada"
  exit 0
fi

# Calcula grupos equilibrados entre as janelas.
# Com menos de 4 instituicoes, mantemos tudo na janela 00s.
# Exemplo: 21 instituicoes => base 5, resto 1 => grupos 6, 5, 5, 5.
total_tenants="$#"

if [ "$total_tenants" -lt "$WINDOW_COUNT" ]; then
  active_window_count=1
else
  active_window_count="$WINDOW_COUNT"
fi

base_group_size=$((total_tenants / active_window_count))
remainder=$((total_tenants % active_window_count))
window_number=1
group_index=0
delay=0
group_tenants=""
group_size="$base_group_size"

# -le significa "less than or equal to"
# Se for menor ou igual ao resto, soma 1 ao grupo size, para distribuir o resto.
# Exemplo: 21 instituicoes => base 5, resto 1 => grupos 6, 5, 5, 5.
if [ "$window_number" -le "$remainder" ]; then
  group_size=$((group_size + 1))
fi

log_distributor "DISTRIBUTE: total $total_tenants, windows $active_window_count, base $base_group_size, remainder $remainder"

for tenant in "$@"; do
  # $((...)) faz aritmetica inteira no shell.
  group_index=$((group_index + 1))
  group_tenants="$group_tenants $tenant"

  # Quando o grupo chega ao tamanho calculado para a janela atual,
  # agenda esse grupo e passa para a proxima janela de 15 segundos.
  if [ "$group_index" -eq "$group_size" ]; then
    run_group "$delay" $group_tenants
    window_number=$((window_number + 1))
    delay=$((delay + WINDOW_STEP_SECONDS))
    group_index=0
    group_tenants=""

    group_size="$base_group_size"

    if [ "$window_number" -le "$remainder" ]; then
      group_size=$((group_size + 1))
    fi
  fi
done

# Em condicoes normais nao sobra nada aqui, porque os grupos foram calculados
# para consumir todas as instituicoes. Esta protecao evita perder itens caso
# o algoritmo seja ajustado no futuro.
if [ "$group_index" -gt 0 ]; then
  run_group "$delay" $group_tenants
fi

FINAL_STATUS=0

# wait aguarda um processo em background terminar.
# Se algum grupo falhar, o script termina com status 1.
for pid in $PIDS; do
  wait "$pid" || FINAL_STATUS=1
done

exit "$FINAL_STATUS"
