#!/usr/bin/env sh

# Esta linha faz o shell encerrar o script se alguma variavel nao definida for
# lida. Sem isso, um erro de nome de variavel poderia virar texto vazio e passar
# despercebido.
set -u

# Define os diretorios onde o shell deve procurar comandos externos. Isso e
# importante quando o script roda pelo crontab, porque o cron costuma ter um
# PATH menor que o terminal interativo. O valor antigo de PATH e mantido no fim.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Calcula o diretorio raiz do projeto a partir do local deste script. "$0" e o
# caminho usado para chamar o script, dirname pega a pasta scripts, "/.." sobe
# para a raiz, cd entra nela e pwd devolve o caminho absoluto.
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# Define o arquivo que contem a lista de containers Moodle a distribuir.
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"

# Define o script executor real. Este distribuidor apenas agrupa e agenda; quem
# roda docker exec dentro de cada container e o RUNNER.
RUNNER="$PROJECT_DIR/scripts/run-moodle-crons.sh"

# Define a pasta onde ficarao os logs de cron e do distribuidor.
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"

# Define o arquivo de log especifico deste distribuidor.
DISTRIBUTOR_LOG="$LOG_DIR/distributor.log"

# Define a quantidade maxima de janelas dentro de um minuto. Com 4 janelas e
# passo de 15 segundos, os grupos podem iniciar em 00s, 15s, 30s e 45s.
WINDOW_COUNT=4

# Define o intervalo, em segundos, entre uma janela e a proxima.
WINDOW_STEP_SECONDS=15

# Inicializa a lista de PIDs dos processos em background. Em C#, a ideia lembra
# guardar Tasks em uma lista para aguardar todas no final.
PIDS=""

# Cria a pasta de logs se ela ainda nao existir.
mkdir -p "$LOG_DIR"

# Declara uma funcao que imprime a data e hora no formato usado nos logs.
timestamp() {
  # Imprime um timestamp como "2026-06-30 14:25:10".
  date "+%Y-%m-%d %H:%M:%S"
}

# Declara uma funcao para gravar uma linha no log do distribuidor.
log_distributor() {
  # Escreve a mensagem recebida em "$1" no distributor.log com timestamp.
  printf "[%s] %s\n" "$(timestamp)" "$1" >> "$DISTRIBUTOR_LOG"
}

# Declara uma funcao que carrega a lista de containers do arquivo de tenants.
load_tenants() {
  # Verifica se o arquivo de tenants nao existe. "-f" testa se o caminho e um
  # arquivo comum, e "!" inverte o resultado.
  if [ ! -f "$TENANTS_FILE" ]; then
    # Escreve a mensagem de erro em stderr para separar erro da saida normal.
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2

    # Retorna status 1 para indicar falha ao chamador da funcao.
    return 1
  fi

  # Fecha o if que validou a existencia do arquivo de tenants.

  # Processa o arquivo de tenants removendo comentarios e linhas vazias. A
  # primeira expressao do sed remove tudo a partir de "#"; a segunda apaga
  # linhas sem conteudo. A saida impressa por esta funcao sera capturada por
  # quem chama load_tenants.
  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    "$TENANTS_FILE"
}

# Declara a funcao que agenda a execucao de um grupo de containers.
run_group() {
  # Recebe o primeiro argumento da funcao: quantos segundos esperar antes de
  # executar este grupo.
  delay="$1"

  # Remove o primeiro argumento da lista. Depois disso, "$@" contem somente os
  # containers do grupo.
  shift

  # Verifica se, depois de remover o delay, nao sobrou nenhum container.
  if [ "$#" -eq 0 ]; then
    # Retorna sucesso porque grupo vazio nao e erro; apenas nao ha trabalho.
    return 0
  fi

  # Fecha o if que protege contra grupo vazio.

  # Registra no log do distribuidor qual grupo foi agendado e com qual atraso.
  log_distributor "SCHEDULE: delay ${delay}s: $*"

  # Inicia um subshell que primeiro espera o delay e depois chama o script
  # executor com os containers do grupo. O "&" no final coloca esse subshell em
  # background, permitindo agendar os proximos grupos sem esperar este terminar.
  (
    # Aguarda a quantidade de segundos calculada para esta janela.
    sleep "$delay"

    # Chama o executor real, passando cada container do grupo como argumento.
    "$RUNNER" "$@"
  ) &

  # Guarda o PID do processo em background recem-criado. "$!" sempre contem o
  # PID do ultimo processo iniciado em background.
  PIDS="$PIDS $!"
}

# Carrega os tenants do arquivo. Se a funcao falhar, encerra o script com erro.
tenants="$(load_tenants)" || exit 1

# Substitui os argumentos atuais do script pela lista carregada do arquivo.
# Depois disso, "$@" representa os containers lidos de moodle-cron-tenants.txt.
set -- $tenants

# Verifica se a lista carregada esta vazia. "$#" e a quantidade de argumentos,
# equivalente a args.Length em C#.
if [ "$#" -eq 0 ]; then
  # Registra que nao havia nenhuma instituicao configurada.
  log_distributor "SKIP: nenhuma instituicao configurada"

  # Encerra com sucesso porque lista vazia nao e falha tecnica.
  exit 0
fi

# Fecha o if que tratou a lista vazia.

# Guarda a quantidade total de tenants carregados.
total_tenants="$#"

# Se ha menos tenants que janelas, usa apenas uma janela. Isso evita espalhar
# poucas instituicoes ao longo do minuto sem necessidade.
if [ "$total_tenants" -lt "$WINDOW_COUNT" ]; then
  # Mantem todos os tenants na janela inicial de 0 segundo.
  active_window_count=1
else
  # Usa todas as janelas disponiveis.
  active_window_count="$WINDOW_COUNT"
fi

# Fecha o if que definiu quantas janelas serao usadas.

# Calcula o tamanho base de cada grupo usando divisao inteira.
base_group_size=$((total_tenants / active_window_count))

# Calcula o resto da divisao. Esse resto sera distribuido adicionando um tenant
# extra aos primeiros grupos.
remainder=$((total_tenants % active_window_count))

# Inicializa o numero da janela atual. A primeira janela e a janela 1.
window_number=1

# Inicializa a contagem de tenants ja colocados no grupo atual.
group_index=0

# Define o atraso inicial como 0 segundo, ou seja, primeira janela do minuto.
delay=0

# Inicializa a lista textual de containers do grupo atual.
group_tenants=""

# Define o tamanho inicial do grupo como o tamanho base calculado.
group_size="$base_group_size"

# Se a janela atual estiver dentro da quantidade representada pelo resto, este
# grupo recebe um tenant extra. Exemplo: 21 tenants em 4 janelas gera base 5 e
# resto 1; o primeiro grupo fica com 6 e os demais com 5.
if [ "$window_number" -le "$remainder" ]; then
  # Adiciona um tenant extra ao tamanho do grupo atual.
  group_size=$((group_size + 1))
fi

# Fecha o if que distribuiu o resto da divisao para o primeiro grupo.

# Registra no log como a distribuicao foi calculada.
log_distributor "DISTRIBUTE: total $total_tenants, windows $active_window_count, base $base_group_size, remainder $remainder"

# Percorre todos os containers carregados do arquivo de tenants.
for tenant in "$@"; do
  # Incrementa a quantidade de tenants no grupo atual.
  group_index=$((group_index + 1))

  # Acrescenta o tenant atual na lista textual do grupo. Nomes de containers
  # Docker nao devem conter espacos, entao a lista pode ser quebrada depois.
  group_tenants="$group_tenants $tenant"

  # Verifica se o grupo atual atingiu o tamanho calculado para esta janela.
  if [ "$group_index" -eq "$group_size" ]; then
    # Agenda o grupo atual. group_tenants fica sem aspas de proposito para que
    # cada container vire um argumento separado.
    run_group "$delay" $group_tenants

    # Avanca para a proxima janela.
    window_number=$((window_number + 1))

    # Soma 15 segundos ao atraso, produzindo janelas como 0, 15, 30 e 45.
    delay=$((delay + WINDOW_STEP_SECONDS))

    # Zera a contagem para comecar o proximo grupo.
    group_index=0

    # Limpa a lista de containers do grupo atual.
    group_tenants=""

    # Reinicia o tamanho do proximo grupo com o tamanho base.
    group_size="$base_group_size"

    # Se a proxima janela ainda estiver dentro do resto da divisao, ela recebe
    # tambem um tenant extra.
    if [ "$window_number" -le "$remainder" ]; then
      # Adiciona um tenant extra ao proximo grupo.
      group_size=$((group_size + 1))
    fi

    # Fecha o if que ajustou o tamanho do proximo grupo.
  fi

  # Fecha o if que verificou se o grupo atual estava completo.
done

# Fecha o loop que percorreu todos os tenants.

# Em condicoes normais nao sobra nada aqui, porque os grupos foram calculados
# para consumir todos os tenants. Esta protecao evita perder itens se o algoritmo
# for alterado no futuro.
if [ "$group_index" -gt 0 ]; then
  # Agenda qualquer grupo restante que nao tenha sido enviado dentro do loop.
  run_group "$delay" $group_tenants
fi

# Fecha o if de protecao para grupo restante.

# Inicializa o status final como sucesso.
FINAL_STATUS=0

# Percorre todos os PIDs dos grupos iniciados em background.
for pid in $PIDS; do
  # Aguarda o grupo terminar. Se o processo retornar erro, marca FINAL_STATUS
  # como 1, mas continua aguardando os demais grupos.
  wait "$pid" || FINAL_STATUS=1
done

# Fecha o loop que aguardou todos os grupos.

# Encerra o distribuidor com o status acumulado dos grupos.
exit "$FINAL_STATUS"
