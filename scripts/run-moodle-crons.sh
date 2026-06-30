#!/usr/bin/env sh

# Esta linha faz o shell encerrar o script se alguma variavel nao definida for
# lida. Em C#, isso lembra a protecao contra usar uma variavel local antes de
# inicializa-la; no shell, sem esta opcao, o erro poderia virar texto vazio.
set -u

# Define os diretorios onde o shell deve procurar comandos externos. Isso e
# importante quando o script roda pelo crontab, porque o cron costuma ter um
# PATH menor que o terminal interativo. O valor antigo de PATH e mantido no fim.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Calcula o diretorio raiz do projeto a partir do local deste script. "$0" e o
# caminho usado para chamar o script, dirname pega a pasta scripts, "/.." sobe
# para a raiz, cd entra nela e pwd devolve o caminho absoluto.
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# Define a pasta onde cada instituicao tera seu arquivo de log do cron.
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"

# Define a pasta raiz dos locks. Se TMPDIR existir, usa TMPDIR; caso contrario,
# usa /tmp. O lock impede duas execucoes simultaneas do cron da mesma instituicao.
LOCK_ROOT="${TMPDIR:-/tmp}/moodle-cron-locks"

# Define o arquivo padrao com a lista de containers Moodle a processar quando o
# script for chamado sem argumentos.
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"

# Cria a pasta de logs se ela ainda nao existir. A opcao -p evita erro caso a
# pasta ja exista e tambem cria diretorios intermediarios.
mkdir -p "$LOG_DIR"

# Cria a pasta raiz dos locks se ela ainda nao existir.
mkdir -p "$LOCK_ROOT"

# Declara uma funcao que imprime a data e hora no formato usado nos logs.
timestamp() {
  # Imprime um timestamp como "2026-06-30 14:25:10".
  date "+%Y-%m-%d %H:%M:%S"
}

# Declara uma funcao para gravar uma linha no log de uma instituicao.
log_line() {
  # Recebe o primeiro argumento da funcao: o nome do container/instituicao.
  tenant="$1"

  # Recebe o segundo argumento da funcao: a mensagem que sera escrita no log.
  message="$2"

  # Escreve a linha formatada no log da instituicao. "$(timestamp)" captura a
  # saida da funcao timestamp, e ">>" acrescenta no fim do arquivo sem apagar o
  # conteudo anterior.
  printf "[%s] %s\n" "$(timestamp)" "$message" >> "$LOG_DIR/$tenant.log"
}

# Declara uma funcao que carrega a lista padrao de containers do arquivo de
# tenants.
load_default_tenants() {
  # Verifica se o arquivo de tenants nao existe. "-f" testa se o caminho e um
  # arquivo comum, e "!" inverte o resultado.
  if [ ! -f "$TENANTS_FILE" ]; then
    # Escreve a mensagem de erro em stderr. O redirecionamento ">&2" envia o
    # texto para a saida de erro, equivalente a Console.Error em C#.
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2

    # Retorna status 1 para indicar falha ao chamador da funcao.
    return 1
  fi

  # Fecha o if que validou a existencia do arquivo de tenants.

  # Processa o arquivo de tenants removendo comentarios e linhas vazias. A
  # primeira expressao do sed remove tudo a partir de "#"; a segunda apaga
  # linhas sem conteudo. A saida impressa por esta funcao sera capturada por
  # quem chama load_default_tenants.
  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    "$TENANTS_FILE"
}

# Declara a funcao que executa o cron do Moodle para uma instituicao.
run_tenant_cron() {
  # Recebe o nome do container Moodle que sera processado.
  tenant="$1"

  # Monta o caminho do lock exclusivo desta instituicao.
  lock_dir="$LOCK_ROOT/$tenant.lock"

  # Verifica se o container existe. docker inspect retorna erro quando o
  # container nao existe; as saidas normal e de erro sao descartadas porque aqui
  # interessa apenas o status do comando.
  if ! docker inspect "$tenant" >/dev/null 2>&1; then
    # Registra que este tenant foi ignorado porque o container nao foi encontrado.
    log_line "$tenant" "SKIP: container nao existe"

    # Retorna sucesso porque container ausente nao deve impedir os demais crons.
    return 0
  fi

  # Fecha o if que validou a existencia do container.

  # Consulta somente o campo State.Running do container. Se o docker inspect
  # falhar por qualquer motivo, o operador "||" executa printf "false", fazendo
  # o valor padrao ser false.
  running="$(docker inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null || printf "false")"

  # Verifica se o container nao esta rodando. A comparacao textual precisa estar
  # entre aspas para evitar problemas se o valor estiver vazio.
  if [ "$running" != "true" ]; then
    # Registra que o container existe, mas nao esta em execucao.
    log_line "$tenant" "SKIP: container nao esta em execucao"

    # Retorna sucesso porque o script apenas executa crons em containers ativos.
    return 0
  fi

  # Fecha o if que validou se o container esta em execucao.

  # Tenta adquirir o lock criando um diretorio exclusivo. mkdir e atomico: se
  # duas execucoes tentarem criar a mesma pasta, apenas uma consegue. Se falhar,
  # consideramos que um cron anterior ainda esta rodando.
  if ! mkdir "$lock_dir" 2>/dev/null; then
    # Registra que o cron foi ignorado por ja existir execucao em andamento.
    log_line "$tenant" "SKIP: cron anterior ainda esta em execucao"

    # Retorna sucesso porque esta situacao e uma protecao esperada.
    return 0
  fi

  # Fecha o if que tentou criar o lock.

  # Registra o inicio da execucao do cron desta instituicao.
  log_line "$tenant" "START: executando cron"

  # Executa o cron do Moodle dentro do container ja rodando. "-u www-data" usa o
  # usuario do servidor web/PHP. A saida normal e a saida de erro do Moodle sao
  # anexadas ao arquivo de log da instituicao.
  docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php >> "$LOG_DIR/$tenant.log" 2>&1

  # Captura imediatamente o codigo de saida do docker exec. "$?" sempre se
  # refere ao ultimo comando executado; zero significa sucesso.
  status="$?"

  # Verifica se o cron terminou com status zero.
  if [ "$status" -eq 0 ]; then
    # Registra sucesso no log da instituicao.
    log_line "$tenant" "OK: cron finalizado com sucesso"
  else
    # Registra erro no log da instituicao, preservando o status retornado.
    log_line "$tenant" "ERROR: cron finalizado com status $status"
  fi

  # Fecha o if que avaliou o status do cron.

  # Remove o lock para liberar proximas execucoes. Erros sao descartados, e
  # "|| true" impede que uma falha ao remover o lock substitua o status real do
  # cron do Moodle.
  rmdir "$lock_dir" 2>/dev/null || true

  # Retorna para o chamador o mesmo status do cron do Moodle.
  return "$status"
}

# Verifica se o script foi chamado sem argumentos. "$#" e a quantidade de
# argumentos, equivalente a args.Length em C#.
if [ "$#" -eq 0 ]; then
  # Carrega os containers do arquivo padrao. Se a funcao falhar, "|| exit 1"
  # encerra o script com erro.
  tenants="$(load_default_tenants)" || exit 1

  # Substitui os argumentos atuais do script pela lista carregada do arquivo.
  # Depois disso, "$@" representa os containers como se tivessem sido passados na
  # linha de comando.
  set -- $tenants
fi

# Inicializa o status final como sucesso. Se qualquer cron falhar, este valor
# sera trocado para 1.
FINAL_STATUS=0

# Percorre todos os containers recebidos por argumento. "$@" preserva cada item
# como um argumento separado, semelhante a percorrer args com foreach em C#.
for tenant in "$@"; do
  # Executa o cron do tenant atual. Se a funcao retornar erro, o operador "||"
  # marca o status final como 1, mas o loop continua para os proximos tenants.
  run_tenant_cron "$tenant" || FINAL_STATUS=1
done

# Encerra o script com o status acumulado. O crontab ou outro chamador consegue
# saber se houve falha em pelo menos uma instituicao.
exit "$FINAL_STATUS"
