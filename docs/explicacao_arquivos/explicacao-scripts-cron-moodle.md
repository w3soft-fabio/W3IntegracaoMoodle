# Explicacao linha a linha dos scripts de cron do Moodle

## Objetivo

Este documento explica os dois scripts shell responsaveis por executar os crons dos containers Moodle:

```text
scripts/run-moodle-crons.sh
scripts/run-moodle-crons-distributed.sh
```

As referencias de linha abaixo consideram a versao atual dos arquivos, ja com os comentarios explicativos inseridos diretamente nos scripts.

Como voce tem base em C#, as explicacoes usam comparacoes com conceitos como `args`, `foreach`, retorno de metodo, `Process`, status de saida e tarefas em paralelo.

## Visao geral

O script `scripts/run-moodle-crons.sh` e o executor real. Ele recebe uma lista de containers Moodle e, para cada container:

- verifica se o container existe;
- verifica se o container esta rodando;
- cria um lock por instituicao;
- executa o cron do Moodle com `docker exec`;
- grava logs por instituicao;
- retorna erro se algum cron falhar.

O script `scripts/run-moodle-crons-distributed.sh` e o distribuidor. Ele:

- le a lista de containers;
- divide a lista em grupos;
- agenda grupos em janelas de 0, 15, 30 e 45 segundos;
- chama `run-moodle-crons.sh` para cada grupo.

## Conceitos de shell usados nos scripts

`$1`, `$2`: parametros posicionais de uma funcao ou script. Em C#, pense nos parametros de um metodo.

`$@`: todos os argumentos, preservando cada item separado. Em C#, pense em `string[] args`.

`$#`: quantidade de argumentos. Em C#, seria `args.Length`.

`$?`: codigo de saida do ultimo comando executado. Em C#, lembra `Process.ExitCode`.

`$!`: PID do ultimo processo iniciado em background. Em C#, lembra guardar uma referencia de `Task` para aguardar depois.

`$(comando)`: executa um comando e captura sua saida como texto.

`||`: executa o lado direito somente se o comando da esquerda falhar.

`>>`: acrescenta conteudo no final de um arquivo.

`2>&1`: envia a saida de erro para o mesmo destino da saida normal.

`$((...))`: faz aritmetica inteira.

## `scripts/run-moodle-crons.sh`

Este arquivo tem 192 linhas na versao atual.

### Linhas 1 a 6: inicializacao segura

Linha 1:

```sh
#!/usr/bin/env sh
```

Define que o arquivo deve ser executado com `sh`. Essa linha e o `shebang`.

Linhas 3 a 5:

```sh
# Esta linha faz o shell encerrar o script se alguma variavel nao definida for
# lida. Em C#, isso lembra a protecao contra usar uma variavel local antes de
# inicializa-la; no shell, sem esta opcao, o erro poderia virar texto vazio.
```

Comentam o motivo de usar `set -u`.

Linha 6:

```sh
set -u
```

Faz o script falhar quando tenta ler variavel nao definida. Isso evita bugs silenciosos.

### Linhas 8 a 27: caminhos principais

Linhas 8 a 10:

```sh
# Define os diretorios onde o shell deve procurar comandos externos. Isso e
# importante quando o script roda pelo crontab, porque o cron costuma ter um
# PATH menor que o terminal interativo. O valor antigo de PATH e mantido no fim.
```

Explicam por que o script define `PATH` manualmente.

Linha 11:

```sh
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

Configura onde o shell procura comandos como `docker`, `mkdir`, `sed`, `date` e `rmdir`.

Linhas 13 a 15:

```sh
# Calcula o diretorio raiz do projeto a partir do local deste script. "$0" e o
# caminho usado para chamar o script, dirname pega a pasta scripts, "/.." sobe
# para a raiz, cd entra nela e pwd devolve o caminho absoluto.
```

Explicam como a raiz do projeto e calculada.

Linha 16:

```sh
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
```

Calcula a raiz do projeto de forma independente do diretorio atual. Em C#, seria parecido com combinar `Path.GetDirectoryName(...)` e `Path.GetFullPath(...)`.

Linhas 18 e 19:

```sh
# Define a pasta onde cada instituicao tera seu arquivo de log do cron.
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
```

Define a pasta dos logs.

Linhas 21 a 23:

```sh
# Define a pasta raiz dos locks. Se TMPDIR existir, usa TMPDIR; caso contrario,
# usa /tmp. O lock impede duas execucoes simultaneas do cron da mesma instituicao.
LOCK_ROOT="${TMPDIR:-/tmp}/moodle-cron-locks"
```

Define onde ficam os locks. `${TMPDIR:-/tmp}` significa: use `TMPDIR` se existir; senao, use `/tmp`.

Linhas 25 a 27:

```sh
# Define o arquivo padrao com a lista de containers Moodle a processar quando o
# script for chamado sem argumentos.
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"
```

Define o arquivo de tenants usado quando o script e chamado sem argumentos.

### Linhas 29 a 40: diretorios e timestamp

Linhas 29 a 31:

```sh
# Cria a pasta de logs se ela ainda nao existir. A opcao -p evita erro caso a
# pasta ja exista e tambem cria diretorios intermediarios.
mkdir -p "$LOG_DIR"
```

Cria a pasta de logs. `-p` evita erro se ela ja existir.

Linhas 33 e 34:

```sh
# Cria a pasta raiz dos locks se ela ainda nao existir.
mkdir -p "$LOCK_ROOT"
```

Cria a pasta dos locks.

Linhas 36 e 37:

```sh
# Declara uma funcao que imprime a data e hora no formato usado nos logs.
timestamp() {
```

Declaram a funcao `timestamp`.

Linhas 38 e 39:

```sh
  # Imprime um timestamp como "2026-06-30 14:25:10".
  date "+%Y-%m-%d %H:%M:%S"
```

Geram a data formatada.

Linha 40:

```sh
}
```

Fecha a funcao.

### Linhas 42 a 54: funcao `log_line`

Linhas 42 e 43:

```sh
# Declara uma funcao para gravar uma linha no log de uma instituicao.
log_line() {
```

Declaram a funcao de log por instituicao.

Linhas 44 e 45:

```sh
  # Recebe o primeiro argumento da funcao: o nome do container/instituicao.
  tenant="$1"
```

Guardam o primeiro argumento em `tenant`.

Linhas 47 e 48:

```sh
  # Recebe o segundo argumento da funcao: a mensagem que sera escrita no log.
  message="$2"
```

Guardam o segundo argumento em `message`.

Linhas 50 a 53:

```sh
  # Escreve a linha formatada no log da instituicao. "$(timestamp)" captura a
  # saida da funcao timestamp, e ">>" acrescenta no fim do arquivo sem apagar o
  # conteudo anterior.
  printf "[%s] %s\n" "$(timestamp)" "$message" >> "$LOG_DIR/$tenant.log"
```

Escrevem uma linha no log da instituicao. Em C#, isso lembra `File.AppendAllText(...)`.

Linha 54:

```sh
}
```

Fecha a funcao.

### Linhas 56 a 80: funcao `load_default_tenants`

Linhas 56 a 58:

```sh
# Declara uma funcao que carrega a lista padrao de containers do arquivo de
# tenants.
load_default_tenants() {
```

Declaram a funcao que le o arquivo `config/moodle-cron-tenants.txt`.

Linhas 59 a 61:

```sh
  # Verifica se o arquivo de tenants nao existe. "-f" testa se o caminho e um
  # arquivo comum, e "!" inverte o resultado.
  if [ ! -f "$TENANTS_FILE" ]; then
```

Verificam se o arquivo nao existe.

Linhas 62 a 64:

```sh
    # Escreve a mensagem de erro em stderr. O redirecionamento ">&2" envia o
    # texto para a saida de erro, equivalente a Console.Error em C#.
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2
```

Escrevem erro em `stderr`.

Linhas 66 a 68:

```sh
    # Retorna status 1 para indicar falha ao chamador da funcao.
    return 1
  fi
```

Retornam falha e fecham o `if`.

Linha 70:

```sh
  # Fecha o if que validou a existencia do arquivo de tenants.
```

Comentario de fechamento, sem efeito no shell.

Linhas 72 a 79:

```sh
  # Processa o arquivo de tenants removendo comentarios e linhas vazias. A
  # primeira expressao do sed remove tudo a partir de "#"; a segunda apaga
  # linhas sem conteudo. A saida impressa por esta funcao sera capturada por
  # quem chama load_default_tenants.
  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    "$TENANTS_FILE"
```

Usam `sed` para remover comentarios e linhas vazias. A funcao retorna a lista imprimindo texto na saida normal.

Linha 80:

```sh
}
```

Fecha a funcao.

### Linhas 82 a 163: funcao `run_tenant_cron`

Linhas 82 a 88:

```sh
# Declara a funcao que executa o cron do Moodle para uma instituicao.
run_tenant_cron() {
  # Recebe o nome do container Moodle que sera processado.
  tenant="$1"

  # Monta o caminho do lock exclusivo desta instituicao.
  lock_dir="$LOCK_ROOT/$tenant.lock"
```

Declaram a funcao principal por instituicao, recebem o container e montam o caminho do lock.

Linhas 90 a 99:

```sh
  # Verifica se o container existe. docker inspect retorna erro quando o
  # container nao existe; as saidas normal e de erro sao descartadas porque aqui
  # interessa apenas o status do comando.
  if ! docker inspect "$tenant" >/dev/null 2>&1; then
    # Registra que este tenant foi ignorado porque o container nao foi encontrado.
    log_line "$tenant" "SKIP: container nao existe"

    # Retorna sucesso porque container ausente nao deve impedir os demais crons.
    return 0
  fi
```

Verificam se o container existe. Se nao existir, registram `SKIP` e retornam sucesso para continuar os demais.

Linhas 101 a 106:

```sh
  # Fecha o if que validou a existencia do container.

  # Consulta somente o campo State.Running do container. Se o docker inspect
  # falhar por qualquer motivo, o operador "||" executa printf "false", fazendo
  # o valor padrao ser false.
  running="$(docker inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null || printf "false")"
```

Consultam se o container esta rodando. O resultado esperado e `true` ou `false`.

Linhas 108 a 116:

```sh
  # Verifica se o container nao esta rodando. A comparacao textual precisa estar
  # entre aspas para evitar problemas se o valor estiver vazio.
  if [ "$running" != "true" ]; then
    # Registra que o container existe, mas nao esta em execucao.
    log_line "$tenant" "SKIP: container nao esta em execucao"

    # Retorna sucesso porque o script apenas executa crons em containers ativos.
    return 0
  fi
```

Pulam containers parados.

Linhas 118 a 129:

```sh
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
```

Criam o lock por instituicao. Se o lock ja existe, o cron e ignorado para evitar execucoes simultaneas.

Linhas 131 a 139:

```sh
  # Fecha o if que tentou criar o lock.

  # Registra o inicio da execucao do cron desta instituicao.
  log_line "$tenant" "START: executando cron"

  # Executa o cron do Moodle dentro do container ja rodando. "-u www-data" usa o
  # usuario do servidor web/PHP. A saida normal e a saida de erro do Moodle sao
  # anexadas ao arquivo de log da instituicao.
  docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php >> "$LOG_DIR/$tenant.log" 2>&1
```

Registram o inicio e executam o cron do Moodle dentro do container.

Linhas 141 a 143:

```sh
  # Captura imediatamente o codigo de saida do docker exec. "$?" sempre se
  # refere ao ultimo comando executado; zero significa sucesso.
  status="$?"
```

Capturam o status do `docker exec`.

Linhas 145 a 152:

```sh
  # Verifica se o cron terminou com status zero.
  if [ "$status" -eq 0 ]; then
    # Registra sucesso no log da instituicao.
    log_line "$tenant" "OK: cron finalizado com sucesso"
  else
    # Registra erro no log da instituicao, preservando o status retornado.
    log_line "$tenant" "ERROR: cron finalizado com status $status"
  fi
```

Registram sucesso ou erro conforme o codigo de saida.

Linhas 154 a 159:

```sh
  # Fecha o if que avaliou o status do cron.

  # Remove o lock para liberar proximas execucoes. Erros sao descartados, e
  # "|| true" impede que uma falha ao remover o lock substitua o status real do
  # cron do Moodle.
  rmdir "$lock_dir" 2>/dev/null || true
```

Removem o lock. Isso funciona como um `finally` em C#.

Linhas 161 a 163:

```sh
  # Retorna para o chamador o mesmo status do cron do Moodle.
  return "$status"
}
```

Retornam o mesmo status do cron e fecham a funcao.

### Linhas 165 a 192: fluxo principal

Linhas 165 a 176:

```sh
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
```

Se nenhum container foi informado, carrega a lista padrao e transforma essa lista nos argumentos atuais.

Linhas 178 a 180:

```sh
# Inicializa o status final como sucesso. Se qualquer cron falhar, este valor
# sera trocado para 1.
FINAL_STATUS=0
```

Inicializam o status final.

Linhas 182 a 188:

```sh
# Percorre todos os containers recebidos por argumento. "$@" preserva cada item
# como um argumento separado, semelhante a percorrer args com foreach em C#.
for tenant in "$@"; do
  # Executa o cron do tenant atual. Se a funcao retornar erro, o operador "||"
  # marca o status final como 1, mas o loop continua para os proximos tenants.
  run_tenant_cron "$tenant" || FINAL_STATUS=1
done
```

Executam o cron para cada tenant.

Linhas 190 a 192:

```sh
# Encerra o script com o status acumulado. O crontab ou outro chamador consegue
# saber se houve falha em pelo menos uma instituicao.
exit "$FINAL_STATUS"
```

Finalizam o script com `0` se tudo deu certo, ou `1` se algum cron falhou.

## `scripts/run-moodle-crons-distributed.sh`

Este arquivo tem 255 linhas na versao atual.

### Linhas 1 a 43: configuracao inicial

Linhas 1 a 6:

```sh
#!/usr/bin/env sh

# Esta linha faz o shell encerrar o script se alguma variavel nao definida for
# lida. Sem isso, um erro de nome de variavel poderia virar texto vazio e passar
# despercebido.
set -u
```

Definem o interpretador e ativam erro para variavel nao definida.

Linhas 8 a 16:

```sh
# Define os diretorios onde o shell deve procurar comandos externos. Isso e
# importante quando o script roda pelo crontab, porque o cron costuma ter um
# PATH menor que o terminal interativo. O valor antigo de PATH e mantido no fim.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Calcula o diretorio raiz do projeto a partir do local deste script. "$0" e o
# caminho usado para chamar o script, dirname pega a pasta scripts, "/.." sobe
# para a raiz, cd entra nela e pwd devolve o caminho absoluto.
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
```

Definem `PATH` e calculam a raiz do projeto.

Linhas 18 a 29:

```sh
# Define o arquivo que contem a lista de containers Moodle a distribuir.
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"

# Define o script executor real. Este distribuidor apenas agrupa e agenda; quem
# roda docker exec dentro de cada container e o RUNNER.
RUNNER="$PROJECT_DIR/scripts/run-moodle-crons.sh"

# Define a pasta onde ficarao os logs de cron e do distribuidor.
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"

# Define o arquivo de log especifico deste distribuidor.
DISTRIBUTOR_LOG="$LOG_DIR/distributor.log"
```

Definem arquivos e pastas usados pelo distribuidor.

Linhas 31 a 40:

```sh
# Define a quantidade maxima de janelas dentro de um minuto. Com 4 janelas e
# passo de 15 segundos, os grupos podem iniciar em 00s, 15s, 30s e 45s.
WINDOW_COUNT=4

# Define o intervalo, em segundos, entre uma janela e a proxima.
WINDOW_STEP_SECONDS=15

# Inicializa a lista de PIDs dos processos em background. Em C#, a ideia lembra
# guardar Tasks em uma lista para aguardar todas no final.
PIDS=""
```

Configuram as janelas de distribuicao e a lista de processos em background.

Linhas 42 e 43:

```sh
# Cria a pasta de logs se ela ainda nao existir.
mkdir -p "$LOG_DIR"
```

Criam a pasta de logs.

### Linhas 45 a 79: funcoes auxiliares

Linhas 45 a 49:

```sh
# Declara uma funcao que imprime a data e hora no formato usado nos logs.
timestamp() {
  # Imprime um timestamp como "2026-06-30 14:25:10".
  date "+%Y-%m-%d %H:%M:%S"
}
```

Declaram a funcao de timestamp.

Linhas 51 a 55:

```sh
# Declara uma funcao para gravar uma linha no log do distribuidor.
log_distributor() {
  # Escreve a mensagem recebida em "$1" no distributor.log com timestamp.
  printf "[%s] %s\n" "$(timestamp)" "$1" >> "$DISTRIBUTOR_LOG"
}
```

Gravam mensagens em `logs/moodle-cron/distributor.log`.

Linhas 57 a 79:

```sh
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
```

Carregam a lista de containers, removendo comentarios e linhas vazias.

### Linhas 81 a 116: funcao `run_group`

Linhas 81 a 95:

```sh
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
```

Recebem o delay, removem esse argumento com `shift` e validam se ha containers no grupo.

Linhas 97 a 115:

```sh
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
```

Agenda o grupo em background. O subshell espera `delay` segundos e chama o executor real.

Linha 116:

```sh
}
```

Fecha a funcao.

### Linhas 118 a 185: carregar tenants e calcular grupos

Linhas 118 a 123:

```sh
# Carrega os tenants do arquivo. Se a funcao falhar, encerra o script com erro.
tenants="$(load_tenants)" || exit 1

# Substitui os argumentos atuais do script pela lista carregada do arquivo.
# Depois disso, "$@" representa os containers lidos de moodle-cron-tenants.txt.
set -- $tenants
```

Carregam os tenants e transformam a lista nos argumentos atuais.

Linhas 125 a 133:

```sh
# Verifica se a lista carregada esta vazia. "$#" e a quantidade de argumentos,
# equivalente a args.Length em C#.
if [ "$#" -eq 0 ]; then
  # Registra que nao havia nenhuma instituicao configurada.
  log_distributor "SKIP: nenhuma instituicao configurada"

  # Encerra com sucesso porque lista vazia nao e falha tecnica.
  exit 0
fi
```

Tratam a lista vazia como sucesso.

Linhas 135 a 148:

```sh
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
```

Definem quantas janelas serao usadas.

Linhas 150 a 185:

```sh
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
```

Calculam a divisao equilibrada entre as janelas.

### Linhas 187 a 228: montar e agendar grupos

Linhas 187 a 200:

```sh
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
```

Percorrem tenants e chamam `run_group` quando o grupo fica completo.

Linhas 202 a 228:

```sh
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
```

Avancam a janela, recalculam o tamanho do proximo grupo e fecham o loop.

### Linhas 230 a 255: finalizar

Linhas 230 a 238:

```sh
# Fecha o loop que percorreu todos os tenants.

# Em condicoes normais nao sobra nada aqui, porque os grupos foram calculados
# para consumir todos os tenants. Esta protecao evita perder itens se o algoritmo
# for alterado no futuro.
if [ "$group_index" -gt 0 ]; then
  # Agenda qualquer grupo restante que nao tenha sido enviado dentro do loop.
  run_group "$delay" $group_tenants
fi
```

Agendam um grupo restante, se existir.

Linhas 240 a 243:

```sh
# Fecha o if de protecao para grupo restante.

# Inicializa o status final como sucesso.
FINAL_STATUS=0
```

Inicializam o status final.

Linhas 245 a 250:

```sh
# Percorre todos os PIDs dos grupos iniciados em background.
for pid in $PIDS; do
  # Aguarda o grupo terminar. Se o processo retornar erro, marca FINAL_STATUS
  # como 1, mas continua aguardando os demais grupos.
  wait "$pid" || FINAL_STATUS=1
done
```

Aguardam todos os grupos em background.

Linhas 252 a 255:

```sh
# Fecha o loop que aguardou todos os grupos.

# Encerra o distribuidor com o status acumulado dos grupos.
exit "$FINAL_STATUS"
```

Finalizam o distribuidor com `0` se todos os grupos deram certo, ou `1` se algum grupo falhou.

## Exemplo de distribuicao

Com 10 instituicoes:

```text
total_tenants = 10
active_window_count = 4
base_group_size = 10 / 4 = 2
remainder = 10 % 4 = 2
```

Resultado:

```text
00s: 3 tenants
15s: 3 tenants
30s: 2 tenants
45s: 2 tenants
```

Os dois primeiros grupos recebem um tenant extra porque o resto da divisao e `2`.

## Fluxo equivalente em C#

O distribuidor lembra este fluxo:

```csharp
var tenants = LoadTenants();
var groups = SplitIntoBalancedGroups(tenants, maxGroups: 4);
var tasks = new List<Task>();
var delay = TimeSpan.Zero;

foreach (var group in groups)
{
    var currentDelay = delay;

    tasks.Add(Task.Run(async () =>
    {
        await Task.Delay(currentDelay);
        RunMoodleCrons(group);
    }));

    delay += TimeSpan.FromSeconds(15);
}

await Task.WhenAll(tasks);
```

O executor lembra este fluxo:

```csharp
foreach (var tenant in tenants)
{
    if (!DockerContainerExists(tenant))
    {
        Log(tenant, "SKIP: container nao existe");
        continue;
    }

    if (!DockerContainerIsRunning(tenant))
    {
        Log(tenant, "SKIP: container nao esta em execucao");
        continue;
    }

    if (!TryAcquireLock(tenant))
    {
        Log(tenant, "SKIP: cron anterior ainda esta em execucao");
        continue;
    }

    try
    {
        var status = DockerExecCron(tenant);
        finalStatus = status == 0 ? finalStatus : 1;
    }
    finally
    {
        ReleaseLock(tenant);
    }
}
```

## Comandos uteis

Executar todos os tenants do arquivo:

```sh
scripts/run-moodle-crons.sh
```

Executar tenants especificos:

```sh
scripts/run-moodle-crons.sh moodle_escola_a moodle_escola_b
```

Executar com distribuicao:

```sh
scripts/run-moodle-crons-distributed.sh
```

Ver logs:

```sh
tail -f logs/moodle-cron/distributor.log
tail -f logs/moodle-cron/moodle_escola_a.log
```
