# Explicacao linha a linha dos scripts de cron do Moodle

## Objetivo deste documento

Este documento explica, linha a linha, os dois scripts shell usados para executar os crons dos containers Moodle:

```text
scripts/run-moodle-crons.sh
scripts/run-moodle-crons-distributed.sh
```

A explicacao assume que voce nao tem muita familiaridade com shell, mas conhece C#. Por isso, sempre que fizer sentido, vou comparar os conceitos com ideias comuns em C#, como variaveis, parametros, funcoes, loops, retorno de metodo, codigo de saida e execucao em paralelo.

Linhas em branco foram ignoradas na explicacao porque servem apenas para separar blocos visualmente e nao mudam o comportamento do script.

## Visao geral dos dois scripts

O arquivo `run-moodle-crons.sh` e o executor real. Ele recebe uma lista de containers Moodle e, para cada container:

- verifica se o container existe;
- verifica se esta rodando;
- cria um lock para evitar duas execucoes simultaneas do mesmo cron;
- executa `php /var/www/html/admin/cli/cron.php` dentro do container;
- grava logs separados por instituicao;
- devolve status de erro se algum cron falhar.

O arquivo `run-moodle-crons-distributed.sh` e um distribuidor. Ele nao executa diretamente o cron do Moodle. Em vez disso, ele:

- le a lista de containers;
- divide a lista em grupos;
- agenda cada grupo para rodar em uma janela diferente do mesmo minuto;
- chama `run-moodle-crons.sh` para cada grupo.

Na pratica:

```text
run-moodle-crons-distributed.sh
  chama run-moodle-crons.sh para o grupo 1 aos 00s
  chama run-moodle-crons.sh para o grupo 2 aos 15s
  chama run-moodle-crons.sh para o grupo 3 aos 30s
  chama run-moodle-crons.sh para o grupo 4 aos 45s
```

Isso reduz picos de CPU, memoria, banco e disco quando existem muitas instituicoes.

## Conceitos rapidos de shell para quem vem de C#

### Variaveis

Em shell, criar uma variavel e assim:

```sh
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
```

Nao ha tipo declarado como `string`, `int` ou `bool`. Quase tudo e tratado como texto, e o shell converte para numero quando voce usa aritmetica.

Em C#, isso lembraria:

```csharp
var logDir = $"{projectDir}/logs/moodle-cron";
```

### Usar uma variavel

Para ler uma variavel em shell, usa-se `$`:

```sh
"$LOG_DIR/$tenant.log"
```

Em C#, seria como interpolar:

```csharp
$"{logDir}/{tenant}.log"
```

As aspas em shell sao muito importantes. Elas preservam espacos e caracteres especiais dentro de um unico valor.

### Parametros de funcao

Em shell, dentro de uma funcao:

```sh
tenant="$1"
message="$2"
```

`$1` e o primeiro argumento, `$2` e o segundo.

Em C#, seria parecido com:

```csharp
void LogLine(string tenant, string message)
```

### Todos os argumentos

Em shell:

```sh
"$@"
```

representa todos os argumentos recebidos, preservando cada argumento separadamente.

Em C#, pense em algo como:

```csharp
string[] args
```

### Quantidade de argumentos

Em shell:

```sh
"$#"
```

e a quantidade de argumentos.

Em C#, seria:

```csharp
args.Length
```

### Codigo de saida

Programas em shell terminam com um numero chamado codigo de saida:

- `0` significa sucesso;
- qualquer outro valor normalmente significa erro.

Em C#, isso lembra:

```csharp
return 0;
```

em um `Main`, ou `Environment.ExitCode`.

### Redirecionamento

Em shell:

```sh
>> arquivo.log
```

acrescenta a saida no final do arquivo.

```sh
2>&1
```

manda a saida de erro para o mesmo lugar da saida normal.

## Arquivo `scripts/run-moodle-crons.sh`

Este script e o executor principal. Ele roda o cron do Moodle dentro de cada container informado.

### Linhas 1 a 5: interpretador e modo seguro

Linha 1:

```sh
#!/usr/bin/env sh
```

Essa linha e chamada de `shebang`. Ela diz ao sistema operacional qual interpretador deve executar o arquivo. Aqui, o script pede para ser executado com `sh`.

O comando `/usr/bin/env sh` procura o `sh` no ambiente atual. Isso costuma ser mais portavel do que escrever diretamente `/bin/sh`.

Em C#, seria como dizer: "este arquivo deve ser executado pelo runtime correto". Nao e codigo de negocio; e uma instrucao para o sistema saber como iniciar o script.

Linhas 3 e 4:

```sh
# Faz o script falhar se tentarmos ler uma variavel que nao foi definida.
# Em C#, pense nisso como evitar usar uma variavel local nao inicializada.
```

Comentarios comecam com `#`. Eles nao sao executados.

Aqui o comentario explica a proxima linha. A comparacao com C# e boa: em C#, usar uma variavel local antes de inicializar gera erro de compilacao. Em shell, normalmente isso poderia virar uma string vazia silenciosamente. O `set -u` evita esse tipo de erro escondido.

Linha 5:

```sh
set -u
```

Ativa uma regra de seguranca: se o script tentar usar uma variavel nao definida, ele falha.

Exemplo:

```sh
echo "$NAO_EXISTE"
```

Com `set -u`, isso gera erro. Sem `set -u`, poderia imprimir vazio e continuar, o que dificulta muito detectar bugs.

### Linhas 7 a 16: configuracoes de caminho

Linhas 7 e 8:

```sh
# O cron do sistema costuma rodar com PATH reduzido. Esta linha garante que
# comandos como docker, php, mkdir e sed possam ser encontrados.
```

O `cron` do sistema normalmente executa comandos com poucas variaveis de ambiente. Uma delas e `PATH`, que define onde o sistema procura programas.

Se o `PATH` estiver incompleto, o script pode nao encontrar `docker`, `mkdir`, `sed` ou outros comandos, mesmo que eles funcionem no terminal interativo.

Linha 9:

```sh
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

Define um novo `PATH`, colocando diretorios comuns no inicio e mantendo o valor anterior no final com `:$PATH`.

Em C#, pense nisso como configurar explicitamente uma lista de pastas onde o processo vai procurar executaveis externos.

No macOS com Homebrew, `/opt/homebrew/bin` e comum em Macs Apple Silicon, e `/usr/local/bin` e comum em Macs Intel ou instalacoes antigas.

Linhas 11 e 12:

```sh
# Resolve a pasta raiz do projeto a partir da localizacao deste script.
# Assim o script funciona mesmo quando chamado pelo crontab.
```

O script nao assume que voce esta dentro da pasta do projeto ao executa-lo. Isso e importante porque o `cron` pode chamar o script a partir de outro diretorio.

Linha 13:

```sh
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
```

Essa linha calcula a pasta raiz do projeto.

Por partes:

- `$0` e o caminho usado para chamar o script.
- `dirname -- "$0"` pega a pasta onde o script esta.
- `"/.."` sobe um nivel, da pasta `scripts` para a raiz do projeto.
- `cd -- ...` entra nessa pasta.
- `pwd` imprime o caminho absoluto da pasta atual.
- `$(...)` captura a saida do comando.
- `PROJECT_DIR="..."` guarda essa saida em uma variavel.

Em C#, seria parecido com:

```csharp
var scriptDir = Path.GetDirectoryName(scriptPath);
var projectDir = Path.GetFullPath(Path.Combine(scriptDir, ".."));
```

O trecho `CDPATH=` desativa temporariamente a variavel `CDPATH`, evitando que `cd` imprima informacoes extras que poderiam sujar o resultado.

O `--` apos `cd` e `dirname` ajuda a tratar caminhos que comecam com `-`, evitando que sejam interpretados como opcoes.

Linha 14:

```sh
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
```

Define onde os logs dos crons serao gravados.

Se `PROJECT_DIR` for `/projeto`, entao `LOG_DIR` vira:

```text
/projeto/logs/moodle-cron
```

Linha 15:

```sh
LOCK_ROOT="${TMPDIR:-/tmp}/moodle-cron-locks"
```

Define a pasta raiz dos locks.

O trecho `${TMPDIR:-/tmp}` significa:

- se `TMPDIR` existir e nao estiver vazio, use `TMPDIR`;
- caso contrario, use `/tmp`.

Em C#, seria parecido com:

```csharp
var tmp = string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TMPDIR"))
    ? "/tmp"
    : Environment.GetEnvironmentVariable("TMPDIR");
var lockRoot = $"{tmp}/moodle-cron-locks";
```

Linha 16:

```sh
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"
```

Define o arquivo que contem a lista padrao de containers Moodle. Cada linha desse arquivo representa uma instituicao/container.

### Linhas 18 e 19: criacao de diretorios

Linha 18:

```sh
mkdir -p "$LOG_DIR"
```

Cria a pasta de logs, se ela ainda nao existir.

A opcao `-p` faz duas coisas:

- cria diretorios intermediarios, se necessario;
- nao falha se a pasta ja existir.

Linha 19:

```sh
mkdir -p "$LOCK_ROOT"
```

Cria a pasta onde ficarao os locks de execucao.

Cada instituicao tera um subdiretorio de lock, como:

```text
/tmp/moodle-cron-locks/moodle_escola_a.lock
```

### Linhas 21 a 23: funcao `timestamp`

Linha 21:

```sh
timestamp() {
```

Declara uma funcao shell chamada `timestamp`.

Em C#, seria como:

```csharp
string Timestamp()
{
```

Linha 22:

```sh
  date "+%Y-%m-%d %H:%M:%S"
```

Executa o comando `date` e imprime a data no formato:

```text
2026-06-30 14:25:10
```

Em shell, a saida impressa por uma funcao pode ser capturada por quem chamou a funcao usando `$(timestamp)`.

Linha 23:

```sh
}
```

Fecha a funcao.

### Linhas 25 a 32: funcao `log_line`

Linha 25:

```sh
log_line() {
```

Declara a funcao que grava uma linha de log para uma instituicao.

Linha 26:

```sh
  # Em shell, "$1" e "$2" sao os parametros recebidos pela funcao.
```

Comentario explicando os parametros posicionais.

Linha 27:

```sh
  tenant="$1"
```

Guarda o primeiro argumento da funcao na variavel `tenant`.

Exemplo de chamada:

```sh
log_line "moodle_escola_a" "START: executando cron"
```

Nesse caso, `tenant` recebe `moodle_escola_a`.

Linha 28:

```sh
  message="$2"
```

Guarda o segundo argumento na variavel `message`.

No exemplo acima, `message` recebe `START: executando cron`.

Linha 30:

```sh
  # >> acrescenta no fim do arquivo. Se o arquivo nao existir, ele e criado.
```

Comentario explicando o redirecionamento usado na proxima linha.

Linha 31:

```sh
  printf "[%s] %s\n" "$(timestamp)" "$message" >> "$LOG_DIR/$tenant.log"
```

Grava uma linha no arquivo de log da instituicao.

Por partes:

- `printf` formata texto.
- `[%s] %s\n` e o formato.
- o primeiro `%s` recebe `$(timestamp)`.
- o segundo `%s` recebe `$message`.
- `\n` quebra a linha.
- `>> "$LOG_DIR/$tenant.log"` acrescenta o texto ao final do arquivo.

Se `tenant` for `moodle_escola_a`, o log sera:

```text
logs/moodle-cron/moodle_escola_a.log
```

Um exemplo de linha gravada:

```text
[2026-06-30 14:25:10] START: executando cron
```

Em C#, seria algo como:

```csharp
File.AppendAllText(
    $"{logDir}/{tenant}.log",
    $"[{Timestamp()}] {message}{Environment.NewLine}"
);
```

Linha 32:

```sh
}
```

Fecha a funcao `log_line`.

### Linhas 34 a 46: funcao `load_default_tenants`

Linha 34:

```sh
load_default_tenants() {
```

Declara uma funcao que carrega a lista padrao de instituicoes/containers.

Linha 35:

```sh
  if [ ! -f "$TENANTS_FILE" ]; then
```

Verifica se o arquivo de tenants nao existe.

Por partes:

- `if ...; then` inicia uma condicao.
- `[ ... ]` e o comando de teste do shell.
- `-f "$TENANTS_FILE"` testa se existe um arquivo comum naquele caminho.
- `!` nega o teste.

Em C#, seria parecido com:

```csharp
if (!File.Exists(tenantsFile))
{
```

Linha 36:

```sh
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2
```

Imprime uma mensagem de erro.

O `>&2` manda a mensagem para a saida de erro, chamada `stderr`, em vez da saida normal.

Em C#, seria parecido com:

```csharp
Console.Error.WriteLine($"ERRO: arquivo de instituicoes nao encontrado: {tenantsFile}");
```

Linha 37:

```sh
    return 1
```

Faz a funcao retornar codigo `1`, indicando erro.

Linha 38:

```sh
  fi
```

Fecha o `if`. Em shell, `fi` e `if` ao contrario.

Linha 40:

```sh
  # Remove comentarios e linhas vazias do arquivo de instituicoes.
```

Comentario explicando a limpeza da lista.

Linha 41:

```sh
  # A saida desta funcao vira a lista de containers a processar.
```

Comentario importante: a funcao nao retorna uma lista como `List<string>` em C#. Ela imprime texto, e quem chama captura esse texto.

Linha 42:

```sh
  sed \
```

Inicia o comando `sed`, uma ferramenta de transformacao de texto.

A barra invertida `\` no final da linha significa: "o comando continua na proxima linha".

Linha 43:

```sh
    -e 's/[[:space:]]*#.*$//' \
```

Primeira regra do `sed`: remove comentarios.

Esse padrao remove qualquer trecho que comece com `#`, incluindo espacos antes dele.

Exemplo:

```text
moodle_escola_a  # escola A
```

vira:

```text
moodle_escola_a
```

Linha 44:

```sh
    -e '/^[[:space:]]*$/d' \
```

Segunda regra do `sed`: remove linhas vazias ou linhas que contenham apenas espacos.

Linha 45:

```sh
    "$TENANTS_FILE"
```

Informa ao `sed` qual arquivo deve ser processado.

Linha 46:

```sh
}
```

Fecha a funcao `load_default_tenants`.

### Linhas 48 a 94: funcao `run_tenant_cron`

Linha 48:

```sh
run_tenant_cron() {
```

Declara a funcao que executa o cron de uma instituicao.

Em C#, a assinatura conceitual seria:

```csharp
int RunTenantCron(string tenant)
```

Linha 49:

```sh
  tenant="$1"
```

Pega o primeiro argumento recebido pela funcao e guarda em `tenant`.

Linha 50:

```sh
  lock_dir="$LOCK_ROOT/$tenant.lock"
```

Monta o caminho do lock daquela instituicao.

Exemplo:

```text
/tmp/moodle-cron-locks/moodle_escola_a.lock
```

Esse lock evita que o cron da mesma instituicao rode duas vezes ao mesmo tempo.

Linhas 52 e 53:

```sh
  # >/dev/null descarta a saida normal.
  # 2>&1 manda a saida de erro para o mesmo destino da saida normal.
```

Comentarios explicando redirecionamento.

`/dev/null` e como uma lixeira de saida. Tudo que e enviado para la e descartado.

Linha 54:

```sh
  if ! docker inspect "$tenant" >/dev/null 2>&1; then
```

Verifica se o container existe.

Por partes:

- `docker inspect "$tenant"` tenta obter detalhes do container.
- `>/dev/null` descarta a saida normal.
- `2>&1` tambem descarta erros, porque envia erro para a mesma saida normal descartada.
- `!` inverte o resultado.

Se `docker inspect` falhar, significa que o container nao existe ou nao pode ser inspecionado.

Em C#, seria conceitualmente:

```csharp
if (!DockerContainerExists(tenant))
{
```

Linha 55:

```sh
    log_line "$tenant" "SKIP: container nao existe"
```

Grava no log da instituicao que ela foi ignorada porque o container nao existe.

Linha 56:

```sh
    return 0
```

Retorna sucesso, mesmo pulando a instituicao.

Essa decisao e importante: container ausente nao faz o script inteiro falhar. Ele apenas registra o problema e segue para os proximos.

Linha 57:

```sh
  fi
```

Fecha o `if`.

Linha 59:

```sh
  # Captura se o container esta rodando. Se o docker inspect falhar, assume false.
```

Comentario explicando a proxima linha.

Linha 60:

```sh
  running="$(docker inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null || printf "false")"
```

Consulta se o container esta rodando e guarda o resultado na variavel `running`.

Por partes:

- `docker inspect --format '{{.State.Running}}' "$tenant"` imprime somente o campo `State.Running` do container.
- Esse campo normalmente vem como `true` ou `false`.
- `2>/dev/null` descarta mensagens de erro.
- `|| printf "false"` significa: se o comando da esquerda falhar, execute `printf "false"`.
- `$(...)` captura a saida do comando.

Em C#, seria parecido com:

```csharp
var running = TryGetContainerRunning(tenant) ?? false;
```

Linha 62:

```sh
  if [ "$running" != "true" ]; then
```

Se o valor de `running` nao for exatamente `true`, entra no bloco.

Em C#:

```csharp
if (running != true)
{
```

Linha 63:

```sh
    log_line "$tenant" "SKIP: container nao esta em execucao"
```

Registra que o container existe, mas nao esta rodando.

Linha 64:

```sh
    return 0
```

Retorna sucesso e segue a vida. O script nao tenta iniciar o container; ele apenas executa crons em containers que ja estao de pe.

Linha 65:

```sh
  fi
```

Fecha o `if`.

Linhas 67 e 68:

```sh
  # mkdir e atomico: se a pasta ja existir, outro cron esta em andamento.
  # Isso funciona como um lock simples por instituicao.
```

Explicam a tecnica de lock.

Criar diretorio com `mkdir` e uma operacao atomica no sistema de arquivos: duas execucoes concorrentes nao conseguem criar a mesma pasta ao mesmo tempo. Uma vence, a outra falha.

Linha 69:

```sh
  if ! mkdir "$lock_dir" 2>/dev/null; then
```

Tenta criar o diretorio de lock.

Se falhar, provavelmente o lock ja existe, ou seja, ja existe um cron daquela instituicao rodando.

Em C#, a ideia seria parecida com tentar criar um recurso exclusivo e, se ele ja existir, desistir:

```csharp
if (!TryAcquireLock(tenant))
{
```

Linha 70:

```sh
    log_line "$tenant" "SKIP: cron anterior ainda esta em execucao"
```

Registra que o cron foi pulado porque havia uma execucao anterior em andamento.

Linha 71:

```sh
    return 0
```

Retorna sucesso, porque isso nao e tratado como erro fatal. E uma protecao esperada.

Linha 72:

```sh
  fi
```

Fecha o `if`.

Linha 74:

```sh
  log_line "$tenant" "START: executando cron"
```

Grava no log que o cron dessa instituicao vai comecar.

Linhas 76 e 77:

```sh
  # Executa o cron dentro do container como www-data.
  # Toda a saida do Moodle e anexada ao log da instituicao.
```

Comentarios explicando o comando principal.

Linha 78:

```sh
  docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php >> "$LOG_DIR/$tenant.log" 2>&1
```

Esta e a linha principal do script. Ela executa o cron do Moodle dentro do container.

Por partes:

- `docker exec` executa um comando dentro de um container ja rodando.
- `-u www-data` executa como usuario `www-data`, que normalmente e o usuario do servidor web/PHP dentro do container.
- `"$tenant"` e o nome do container.
- `php /var/www/html/admin/cli/cron.php` e o comando executado dentro do container.
- `>> "$LOG_DIR/$tenant.log"` anexa a saida normal ao log da instituicao.
- `2>&1` anexa tambem a saida de erro ao mesmo log.

Em C#, pense em algo como iniciar um `Process` externo:

```csharp
Process.Start("docker", $"exec -u www-data {tenant} php /var/www/html/admin/cli/cron.php");
```

com redirecionamento de stdout e stderr para um arquivo.

Linhas 80 e 81:

```sh
  # "$?" e o codigo de saida do ultimo comando executado.
  # Zero significa sucesso; qualquer outro valor indica erro.
```

Comentarios sobre a variavel especial `$?`.

Linha 82:

```sh
  status="$?"
```

Guarda o codigo de saida do `docker exec`.

Isso precisa acontecer logo depois do comando, porque `$?` sempre se refere ao ultimo comando executado.

Em C#, seria parecido com ler:

```csharp
var status = process.ExitCode;
```

Linha 84:

```sh
  if [ "$status" -eq 0 ]; then
```

Verifica se o status e igual a zero.

`-eq` significa "numericamente igual". Em shell, para numeros voce usa operadores como `-eq`, `-ne`, `-lt`, `-gt`, em vez de `==`.

Em C#:

```csharp
if (status == 0)
{
```

Linha 85:

```sh
    log_line "$tenant" "OK: cron finalizado com sucesso"
```

Registra sucesso.

Linha 86:

```sh
  else
```

Inicia o bloco alternativo.

Linha 87:

```sh
    log_line "$tenant" "ERROR: cron finalizado com status $status"
```

Registra erro, incluindo o codigo de saida.

Linha 88:

```sh
  fi
```

Fecha o `if`.

Linha 90:

```sh
  rmdir "$lock_dir" 2>/dev/null || true
```

Remove o diretorio de lock.

Por partes:

- `rmdir "$lock_dir"` remove o diretorio.
- `2>/dev/null` esconde erro, caso o diretorio ja tenha sumido por algum motivo.
- `|| true` garante que essa linha nao faca a funcao falhar.

Isso e parecido com um `finally` em C#: mesmo apos o cron terminar, o lock precisa ser liberado.

Conceitualmente:

```csharp
finally
{
    ReleaseLock();
}
```

Linha 92:

```sh
  # Retorna para quem chamou a funcao o mesmo status do cron do Moodle.
```

Comentario sobre o retorno da funcao.

Linha 93:

```sh
  return "$status"
```

Retorna o mesmo codigo de saida do `docker exec`.

Se o cron do Moodle falhou, a funcao tambem falha. Isso permite que o script principal marque `FINAL_STATUS=1`.

Linha 94:

```sh
}
```

Fecha a funcao `run_tenant_cron`.

### Linhas 96 a 104: carregar lista padrao quando nenhum argumento foi passado

Linhas 96 e 97:

```sh
# "$#" e a quantidade de argumentos recebidos pelo script.
# Se nenhum container foi informado na linha de comando, carregamos a lista padrao.
```

Comentarios explicando o uso de `$#`.

Linha 98:

```sh
if [ "$#" -eq 0 ]; then
```

Verifica se o script foi chamado sem argumentos.

Em C#:

```csharp
if (args.Length == 0)
{
```

Linha 99:

```sh
  tenants="$(load_default_tenants)" || exit 1
```

Chama a funcao `load_default_tenants` e captura a saida dela na variavel `tenants`.

Se a funcao falhar, `|| exit 1` encerra o script com erro.

Em C#, seria algo como:

```csharp
var tenants = LoadDefaultTenants();
if (tenants == null)
{
    return 1;
}
```

Linha 101:

```sh
  # set -- substitui os argumentos atuais do script.
```

Comentario explicando a proxima linha.

Linha 102:

```sh
  # Depois desta linha, "$@" passa a representar as instituicoes do arquivo.
```

Mais um comentario: o script transforma a lista carregada do arquivo nos argumentos atuais.

Linha 103:

```sh
  set -- $tenants
```

Substitui os argumentos atuais do script pela lista de tenants.

Se `tenants` contem:

```text
moodle_escola_a
moodle_escola_b
```

entao depois dessa linha:

```sh
"$@"
```

passa a representar:

```text
moodle_escola_a moodle_escola_b
```

Em C#, seria como substituir `args` por uma lista carregada de arquivo.

Linha 104:

```sh
fi
```

Fecha o `if`.

### Linhas 106 a 114: executar todos os tenants e sair com status final

Linha 106:

```sh
FINAL_STATUS=0
```

Inicializa o status final como sucesso.

Em C#:

```csharp
var finalStatus = 0;
```

Linha 108:

```sh
# "$@" representa todos os argumentos, preservando cada item como um argumento.
```

Comentario sobre a iteracao.

Linha 109:

```sh
for tenant in "$@"; do
```

Inicia um loop sobre todos os argumentos.

Em C#:

```csharp
foreach (var tenant in args)
{
```

Linha 110:

```sh
  run_tenant_cron "$tenant" || FINAL_STATUS=1
```

Executa o cron de um tenant.

Se `run_tenant_cron "$tenant"` falhar, ou seja, retornar codigo diferente de zero, o trecho apos `||` e executado:

```sh
FINAL_STATUS=1
```

Isso significa: "continue processando os proximos tenants, mas lembre que houve pelo menos uma falha".

Em C#, seria:

```csharp
if (RunTenantCron(tenant) != 0)
{
    finalStatus = 1;
}
```

Linha 111:

```sh
done
```

Fecha o loop `for`.

Linha 113:

```sh
# O codigo de saida final permite que o crontab/shell saiba se houve erro.
```

Comentario explicando por que o script termina com um status calculado.

Linha 114:

```sh
exit "$FINAL_STATUS"
```

Encerra o script com o status final.

Se todos os crons executados retornaram sucesso, sai com `0`.

Se pelo menos um cron falhou, sai com `1`.

## Arquivo `scripts/run-moodle-crons-distributed.sh`

Este script distribui a execucao dos crons ao longo do minuto. Ele cria grupos de containers e agenda cada grupo com um atraso diferente.

Ele depende do script anterior:

```text
scripts/run-moodle-crons.sh
```

### Linhas 1 a 4: interpretador e modo seguro

Linha 1:

```sh
#!/usr/bin/env sh
```

Define que o script deve ser executado com `sh`.

Linha 3:

```sh
# Faz o script falhar se tentarmos ler uma variavel que nao foi definida.
```

Comentario explicando a proxima linha.

Linha 4:

```sh
set -u
```

Ativa erro ao usar variavel nao definida, como no script anterior.

### Linhas 6 a 15: variaveis de configuracao

Linhas 6 e 7:

```sh
# O cron do sistema costuma ter PATH reduzido. Incluimos os caminhos comuns
# para o shell encontrar docker, sed, sleep e os demais comandos.
```

Comentarios sobre `PATH`, especialmente importante quando o script roda via `crontab`.

Linha 8:

```sh
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

Define os caminhos onde o shell deve procurar comandos externos.

Linha 10:

```sh
# Resolve a pasta raiz do projeto a partir da localizacao deste script.
```

Comentario explicando a proxima linha.

Linha 11:

```sh
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
```

Calcula a pasta raiz do projeto a partir da localizacao do proprio script.

E a mesma ideia usada no outro arquivo:

- pega a pasta do script;
- sobe um nivel;
- converte para caminho absoluto.

Linha 12:

```sh
TENANTS_FILE="$PROJECT_DIR/config/moodle-cron-tenants.txt"
```

Define o arquivo que contem a lista de containers Moodle.

Linha 13:

```sh
RUNNER="$PROJECT_DIR/scripts/run-moodle-crons.sh"
```

Define o caminho do script executor.

Este distribuidor nao roda `docker exec` diretamente. Ele chama o `RUNNER`, que e o `run-moodle-crons.sh`.

Linha 14:

```sh
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
```

Define a pasta de logs.

Linha 15:

```sh
DISTRIBUTOR_LOG="$LOG_DIR/distributor.log"
```

Define o arquivo de log especifico do distribuidor.

Enquanto o executor grava logs por instituicao, o distribuidor grava eventos de distribuicao em:

```text
logs/moodle-cron/distributor.log
```

### Linhas 17 a 23: configuracao das janelas e PIDs

Linhas 17 e 18:

```sh
# O minuto sera dividido em 4 janelas fixas: 00s, 15s, 30s e 45s.
# A quantidade de instituicoes por janela e calculada dinamicamente.
```

Comentarios explicando a estrategia.

O script divide o minuto em ate quatro janelas:

```text
0 segundos
15 segundos
30 segundos
45 segundos
```

Linha 19:

```sh
WINDOW_COUNT=4
```

Define a quantidade maxima de janelas.

Linha 20:

```sh
WINDOW_STEP_SECONDS=15
```

Define o intervalo entre as janelas.

Com `4` janelas e passo de `15` segundos, temos:

```text
0, 15, 30, 45
```

Linha 22:

```sh
# Guarda os IDs dos processos iniciados em background.
```

Comentario explicando `PIDS`.

Linha 23:

```sh
PIDS=""
```

Inicializa uma string vazia que guardara os IDs dos processos em background.

Em C#, pense em algo como:

```csharp
var tasks = new List<Task>();
```

Nao e exatamente igual, mas a ideia e guardar referencias para esperar depois.

### Linhas 25 a 34: preparar logs e funcoes basicas

Linha 25:

```sh
mkdir -p "$LOG_DIR"
```

Cria a pasta de logs, se ela ainda nao existir.

Linha 27:

```sh
timestamp() {
```

Declara a funcao `timestamp`.

Linha 28:

```sh
  date "+%Y-%m-%d %H:%M:%S"
```

Imprime a data e hora formatadas.

Linha 29:

```sh
}
```

Fecha a funcao `timestamp`.

Linha 31:

```sh
log_distributor() {
```

Declara uma funcao para escrever no log do distribuidor.

Linha 32:

```sh
  # "$1" e a mensagem recebida pela funcao.
```

Comentario explicando que `$1` e o primeiro argumento da funcao.

Linha 33:

```sh
  printf "[%s] %s\n" "$(timestamp)" "$1" >> "$DISTRIBUTOR_LOG"
```

Grava uma linha no `distributor.log`.

Exemplo:

```text
[2026-06-30 14:25:00] DISTRIBUTE: total 21, windows 4, base 5, remainder 1
```

Linha 34:

```sh
}
```

Fecha a funcao `log_distributor`.

### Linhas 36 a 47: funcao `load_tenants`

Linha 36:

```sh
load_tenants() {
```

Declara a funcao que carrega a lista de instituicoes.

Linha 37:

```sh
  if [ ! -f "$TENANTS_FILE" ]; then
```

Verifica se o arquivo de tenants nao existe.

Linha 38:

```sh
    printf "ERRO: arquivo de instituicoes nao encontrado: %s\n" "$TENANTS_FILE" >&2
```

Imprime uma mensagem de erro em `stderr`.

Linha 39:

```sh
    return 1
```

Retorna erro da funcao.

Linha 40:

```sh
  fi
```

Fecha o `if`.

Linha 42:

```sh
  # Remove comentarios e linhas vazias do arquivo de instituicoes.
```

Comentario explicando a limpeza do arquivo.

Linha 43:

```sh
  sed \
```

Inicia o `sed`.

Linha 44:

```sh
    -e 's/[[:space:]]*#.*$//' \
```

Remove comentarios no final das linhas.

Linha 45:

```sh
    -e '/^[[:space:]]*$/d' \
```

Remove linhas vazias.

Linha 46:

```sh
    "$TENANTS_FILE"
```

Indica o arquivo de entrada.

Linha 47:

```sh
}
```

Fecha a funcao `load_tenants`.

### Linhas 49 a 74: funcao `run_group`

Linha 49:

```sh
run_group() {
```

Declara a funcao que agenda a execucao de um grupo de tenants.

Conceitualmente, em C# seria algo como:

```csharp
Task RunGroupAfterDelay(int delay, string[] tenants)
```

Linha 50:

```sh
  # Primeiro argumento: quantos segundos esperar antes de executar o grupo.
```

Comentario explicando o primeiro parametro.

Linha 51:

```sh
  delay="$1"
```

Guarda o primeiro argumento em `delay`.

Exemplo:

```sh
run_group 15 moodle_escola_b moodle_escola_c
```

Nesse caso, `delay` vale `15`.

Linhas 53 e 54:

```sh
  # shift descarta o primeiro argumento.
  # Depois disso, "$@" contem somente os containers do grupo.
```

Comentarios sobre `shift`.

Linha 55:

```sh
  shift
```

Remove o primeiro argumento da lista de argumentos da funcao.

Antes do `shift`:

```text
$1 = 15
$2 = moodle_escola_b
$3 = moodle_escola_c
```

Depois do `shift`:

```text
$1 = moodle_escola_b
$2 = moodle_escola_c
```

E `"$@"` passa a conter apenas os tenants.

Linha 57:

```sh
  if [ "$#" -eq 0 ]; then
```

Verifica se, depois do `shift`, nao sobrou nenhum tenant.

Linha 58:

```sh
    return 0
```

Se o grupo esta vazio, a funcao termina com sucesso sem fazer nada.

Linha 59:

```sh
  fi
```

Fecha o `if`.

Linha 61:

```sh
  log_distributor "SCHEDULE: delay ${delay}s: $*"
```

Registra no log que um grupo foi agendado.

Detalhes:

- `${delay}` le a variavel `delay`.
- `$*` representa todos os argumentos restantes como texto.

Exemplo de log:

```text
SCHEDULE: delay 15s: moodle_escola_b moodle_escola_c
```

Linhas 63 a 65:

```sh
  # Os parenteses criam um subshell.
  # O & no final inicia esse bloco em background, permitindo agendar
  # os grupos de 00s, 15s, 30s e 45s sem bloquear o script principal.
```

Comentarios explicando o bloco assicrono.

Em shell, parenteses criam um subshell: um processo separado para executar comandos.

Linha 66:

```sh
  (
```

Inicia o subshell.

Linha 67:

```sh
    sleep "$delay"
```

Espera a quantidade de segundos definida.

Se `delay` for `30`, o grupo espera 30 segundos antes de rodar.

Linha 68:

```sh
    "$RUNNER" "$@"
```

Executa o script `run-moodle-crons.sh`, passando todos os tenants do grupo como argumentos.

Exemplo:

```sh
scripts/run-moodle-crons.sh moodle_escola_b moodle_escola_c
```

Linha 69:

```sh
  ) &
```

Fecha o subshell e o executa em background por causa do `&`.

Isso permite que o script principal continue imediatamente e agende os proximos grupos.

Em C#, a ideia lembra iniciar uma `Task` sem bloquear imediatamente:

```csharp
var task = Task.Run(async () =>
{
    await Task.Delay(delay);
    RunMoodleCrons(group);
});
```

Linha 71:

```sh
  # "$!" e o PID do ultimo processo iniciado em background.
```

Comentario sobre a variavel especial `$!`.

Linha 72:

```sh
  # Guardamos para esperar todos terminarem no fim do script.
```

Comentario explicando por que guardar o PID.

Linha 73:

```sh
  PIDS="$PIDS $!"
```

Acrescenta o PID do processo em background na variavel `PIDS`.

`$!` e o ID do ultimo processo iniciado com `&`.

Em C#, e como guardar a `Task` em uma lista para fazer `await Task.WhenAll(tasks)` depois.

Linha 74:

```sh
}
```

Fecha a funcao `run_group`.

### Linhas 76 a 86: carregar tenants e tratar lista vazia

Linha 76:

```sh
tenants="$(load_tenants)" || exit 1
```

Carrega os tenants do arquivo e guarda em `tenants`.

Se `load_tenants` falhar, o script termina com codigo `1`.

Linha 78:

```sh
# set -- substitui os argumentos atuais do script pela lista de instituicoes.
```

Comentario explicando `set --`.

Linha 79:

```sh
# A partir daqui, "$@" representa os containers lidos do arquivo.
```

Comentario reforcando que `"$@"` passa a ser a lista do arquivo.

Linha 80:

```sh
set -- $tenants
```

Transforma a lista textual de tenants em argumentos do script.

Linha 82:

```sh
# "$#" e a quantidade de argumentos atuais, ou seja, de instituicoes carregadas.
```

Comentario explicando `$#`.

Linha 83:

```sh
if [ "$#" -eq 0 ]; then
```

Verifica se nenhum tenant foi carregado.

Linha 84:

```sh
  log_distributor "SKIP: nenhuma instituicao configurada"
```

Registra que nao havia nada para executar.

Linha 85:

```sh
  exit 0
```

Encerra com sucesso. Lista vazia nao e erro tecnico.

Linha 86:

```sh
fi
```

Fecha o `if`.

### Linhas 88 a 114: calcular tamanho dos grupos

Linhas 88 a 90:

```sh
# Calcula grupos equilibrados entre as janelas.
# Com menos de 4 instituicoes, mantemos tudo na janela 00s.
# Exemplo: 21 instituicoes => base 5, resto 1 => grupos 6, 5, 5, 5.
```

Comentarios explicando a regra de distribuicao.

Se existem muitas instituicoes, o script divide em ate 4 grupos. Se existem menos de 4 instituicoes, ele roda tudo na primeira janela, para evitar espalhar poucos itens desnecessariamente.

Linha 91:

```sh
total_tenants="$#"
```

Guarda a quantidade total de tenants.

Em C#:

```csharp
var totalTenants = args.Length;
```

Linha 93:

```sh
if [ "$total_tenants" -lt "$WINDOW_COUNT" ]; then
```

Se o total de tenants for menor que a quantidade de janelas, entra no bloco.

`-lt` significa "less than", ou seja, menor que.

Linha 94:

```sh
  active_window_count=1
```

Usa apenas uma janela ativa.

Exemplo: se ha 2 tenants e 4 janelas possiveis, os 2 rodam aos 0 segundos.

Linha 95:

```sh
else
```

Inicia o bloco alternativo.

Linha 96:

```sh
  active_window_count="$WINDOW_COUNT"
```

Se ha tenants suficientes, usa as 4 janelas.

Linha 97:

```sh
fi
```

Fecha o `if`.

Linha 99:

```sh
base_group_size=$((total_tenants / active_window_count))
```

Calcula o tamanho base de cada grupo com divisao inteira.

`$((...))` executa aritmetica inteira em shell.

Exemplo com 21 tenants e 4 janelas:

```text
21 / 4 = 5
```

O resultado inteiro e `5`.

Linha 100:

```sh
remainder=$((total_tenants % active_window_count))
```

Calcula o resto da divisao.

Exemplo:

```text
21 % 4 = 1
```

Isso significa que um grupo recebera uma instituicao extra.

Linha 101:

```sh
window_number=1
```

Inicializa o numero da janela atual em `1`.

Linha 102:

```sh
group_index=0
```

Inicializa a quantidade de tenants ja colocados no grupo atual.

Linha 103:

```sh
delay=0
```

Define que o primeiro grupo roda sem atraso, ou seja, aos 0 segundos.

Linha 104:

```sh
group_tenants=""
```

Inicializa a lista textual de tenants do grupo atual como vazia.

Linha 105:

```sh
group_size="$base_group_size"
```

Define que o tamanho do grupo atual comeca com o tamanho base.

Linhas 107 a 109:

```sh
# -le significa "less than or equal to"
# Se for menor ou igual ao resto, soma 1 ao grupo size, para distribuir o resto.
# Exemplo: 21 instituicoes => base 5, resto 1 => grupos 6, 5, 5, 5.
```

Comentarios explicando como o resto da divisao e distribuido.

Linha 110:

```sh
if [ "$window_number" -le "$remainder" ]; then
```

Se o numero da janela atual for menor ou igual ao resto, este grupo recebe mais um item.

`-le` significa "less than or equal to", ou seja, menor ou igual.

Linha 111:

```sh
  group_size=$((group_size + 1))
```

Soma `1` ao tamanho do grupo.

Exemplo com 21 tenants:

- base: `5`;
- remainder: `1`;
- janela 1 recebe `5 + 1 = 6`;
- janelas 2, 3 e 4 recebem `5`.

Linha 112:

```sh
fi
```

Fecha o `if`.

Linha 114:

```sh
log_distributor "DISTRIBUTE: total $total_tenants, windows $active_window_count, base $base_group_size, remainder $remainder"
```

Registra no log como a distribuicao foi calculada.

Exemplo:

```text
DISTRIBUTE: total 21, windows 4, base 5, remainder 1
```

### Linhas 116 a 136: montar e agendar os grupos

Linha 116:

```sh
for tenant in "$@"; do
```

Inicia um loop por todos os tenants carregados.

Em C#:

```csharp
foreach (var tenant in tenants)
{
```

Linha 117:

```sh
  # $((...)) faz aritmetica inteira no shell.
```

Comentario sobre a proxima linha.

Linha 118:

```sh
  group_index=$((group_index + 1))
```

Incrementa a contagem de itens dentro do grupo atual.

Em C#:

```csharp
groupIndex++;
```

Linha 119:

```sh
  group_tenants="$group_tenants $tenant"
```

Acrescenta o tenant atual na lista textual do grupo.

Exemplo:

```text
 moodle_escola_a moodle_escola_b
```

Repare que essa lista e uma string. Isso funciona bem se os nomes dos containers nao tiverem espacos, o que e normal em nomes Docker.

Linhas 121 e 122:

```sh
  # Quando o grupo chega ao tamanho calculado para a janela atual,
  # agenda esse grupo e passa para a proxima janela de 15 segundos.
```

Comentarios explicando a condicao.

Linha 123:

```sh
  if [ "$group_index" -eq "$group_size" ]; then
```

Verifica se o grupo atual atingiu o tamanho planejado.

Linha 124:

```sh
    run_group "$delay" $group_tenants
```

Agenda o grupo atual para executar apos o atraso atual.

Importante: aqui `group_tenants` nao esta entre aspas de proposito. Isso faz a string ser quebrada em varios argumentos, um por tenant.

Exemplo:

```sh
run_group 15 moodle_escola_b moodle_escola_c
```

Se estivesse como `"$group_tenants"`, todos os tenants seriam passados como um unico argumento, o que quebraria a logica.

Linha 125:

```sh
    window_number=$((window_number + 1))
```

Avanca para a proxima janela.

Linha 126:

```sh
    delay=$((delay + WINDOW_STEP_SECONDS))
```

Soma 15 segundos ao atraso.

Assim, os delays ficam:

```text
0, 15, 30, 45
```

Linha 127:

```sh
    group_index=0
```

Zera a contagem do grupo atual para comecar um novo grupo.

Linha 128:

```sh
    group_tenants=""
```

Limpa a lista textual de tenants do grupo atual.

Linha 130:

```sh
    group_size="$base_group_size"
```

Reinicia o tamanho do proximo grupo com o tamanho base.

Linha 132:

```sh
    if [ "$window_number" -le "$remainder" ]; then
```

Verifica se a proxima janela ainda deve receber uma instituicao extra por causa do resto da divisao.

Linha 133:

```sh
      group_size=$((group_size + 1))
```

Soma `1` ao tamanho do proximo grupo, se necessario.

Linha 134:

```sh
    fi
```

Fecha o `if` interno.

Linha 135:

```sh
  fi
```

Fecha o `if` que verifica se o grupo atingiu o tamanho esperado.

Linha 136:

```sh
done
```

Fecha o loop `for`.

### Linhas 138 a 143: protecao para tenants restantes

Linhas 138 a 140:

```sh
# Em condicoes normais nao sobra nada aqui, porque os grupos foram calculados
# para consumir todas as instituicoes. Esta protecao evita perder itens caso
# o algoritmo seja ajustado no futuro.
```

Comentarios explicando uma protecao defensiva.

Linha 141:

```sh
if [ "$group_index" -gt 0 ]; then
```

Verifica se ainda existe algum tenant acumulado no grupo atual.

`-gt` significa "greater than", ou seja, maior que.

Linha 142:

```sh
  run_group "$delay" $group_tenants
```

Agenda o grupo restante.

Linha 143:

```sh
fi
```

Fecha o `if`.

### Linhas 145 a 153: aguardar grupos e devolver status final

Linha 145:

```sh
FINAL_STATUS=0
```

Inicializa o status final como sucesso.

Linha 147:

```sh
# wait aguarda um processo em background terminar.
```

Comentario sobre o comando `wait`.

Linha 148:

```sh
# Se algum grupo falhar, o script termina com status 1.
```

Comentario explicando a regra final.

Linha 149:

```sh
for pid in $PIDS; do
```

Inicia um loop por todos os PIDs guardados.

Cada PID representa um grupo agendado em background.

Linha 150:

```sh
  wait "$pid" || FINAL_STATUS=1
```

Aguarda aquele processo terminar.

Se o processo terminar com erro, `FINAL_STATUS` vira `1`.

Em C#, a ideia lembra:

```csharp
foreach (var task in tasks)
{
    try
    {
        await task;
    }
    catch
    {
        finalStatus = 1;
    }
}
```

Linha 151:

```sh
done
```

Fecha o loop.

Linha 153:

```sh
exit "$FINAL_STATUS"
```

Encerra o script com o status final.

Se todos os grupos executaram com sucesso, retorna `0`.

Se algum grupo falhou, retorna `1`.

## Exemplo pratico de distribuicao

Imagine que `config/moodle-cron-tenants.txt` contem 10 containers:

```text
moodle_escola_01
moodle_escola_02
moodle_escola_03
moodle_escola_04
moodle_escola_05
moodle_escola_06
moodle_escola_07
moodle_escola_08
moodle_escola_09
moodle_escola_10
```

O distribuidor calcula:

```text
total_tenants = 10
active_window_count = 4
base_group_size = 10 / 4 = 2
remainder = 10 % 4 = 2
```

Entao os dois primeiros grupos recebem uma instituicao extra:

```text
Grupo 1: 3 tenants, delay 0s
Grupo 2: 3 tenants, delay 15s
Grupo 3: 2 tenants, delay 30s
Grupo 4: 2 tenants, delay 45s
```

Resultado:

```text
00s: moodle_escola_01, moodle_escola_02, moodle_escola_03
15s: moodle_escola_04, moodle_escola_05, moodle_escola_06
30s: moodle_escola_07, moodle_escola_08
45s: moodle_escola_09, moodle_escola_10
```

## Fluxo completo em linguagem de C#

Uma versao conceitual do comportamento seria:

```csharp
var tenants = LoadTenantsFromFile();
var groups = SplitIntoBalancedGroups(tenants, maxGroups: 4);

var tasks = new List<Task>();
var delay = TimeSpan.Zero;

foreach (var group in groups)
{
    var currentDelay = delay;
    tasks.Add(Task.Run(async () =>
    {
        await Task.Delay(currentDelay);
        await RunMoodleCrons(group);
    }));

    delay += TimeSpan.FromSeconds(15);
}

var finalStatus = 0;

foreach (var task in tasks)
{
    try
    {
        await task;
    }
    catch
    {
        finalStatus = 1;
    }
}

return finalStatus;
```

E o executor `RunMoodleCrons(group)` seria conceitualmente:

```csharp
foreach (var tenant in group)
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
        Log(tenant, "START: executando cron");
        var status = DockerExecCronAsWwwData(tenant);

        if (status == 0)
        {
            Log(tenant, "OK: cron finalizado com sucesso");
        }
        else
        {
            Log(tenant, $"ERROR: cron finalizado com status {status}");
            finalStatus = 1;
        }
    }
    finally
    {
        ReleaseLock(tenant);
    }
}
```

## Pontos importantes para lembrar

- `run-moodle-crons.sh` executa o cron de fato.
- `run-moodle-crons-distributed.sh` so distribui a execucao ao longo do minuto.
- `"$@"` e parecido com `args` em C#.
- `"$#"` e parecido com `args.Length`.
- `"$1"`, `"$2"` sao parametros posicionais.
- `$(comando)` captura a saida de um comando.
- `$?` pega o status do ultimo comando.
- `$!` pega o PID do ultimo processo iniciado em background.
- `||` executa o lado direito somente se o lado esquerdo falhar.
- `&&` executaria o lado direito somente se o lado esquerdo tivesse sucesso.
- `>>` anexa texto a um arquivo.
- `2>&1` junta erro e saida normal no mesmo destino.
- `mkdir` usado como lock e uma forma simples de impedir concorrencia por instituicao.
- `wait` e usado para aguardar processos em background.

## Como executar manualmente para testar

Executar todos os tenants do arquivo padrao:

```sh
scripts/run-moodle-crons.sh
```

Executar apenas uma instituicao:

```sh
scripts/run-moodle-crons.sh moodle_escola_a
```

Executar duas instituicoes especificas:

```sh
scripts/run-moodle-crons.sh moodle_escola_a moodle_escola_b
```

Executar com distribuicao em janelas de 15 segundos:

```sh
scripts/run-moodle-crons-distributed.sh
```

Ver log de uma instituicao:

```sh
tail -f logs/moodle-cron/moodle_escola_a.log
```

Ver log do distribuidor:

```sh
tail -f logs/moodle-cron/distributor.log
```
