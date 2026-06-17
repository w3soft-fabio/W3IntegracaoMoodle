# Passo 8: Substituir o container permanente de cron por agendamento central

## Objetivo deste passo

Neste passo, o objetivo e parar de criar um container permanente de cron para cada Moodle e passar a executar o cron de cada instituicao a partir de um agendador central no host.

A ideia principal e:

```text
Antes:
  moodle_escola_a + cron_escola_a
  moodle_escola_b + cron_escola_b
  moodle_escola_c + cron_escola_c

Depois:
  moodle_escola_a
  moodle_escola_b
  moodle_escola_c
  +
  1 agendador central no host executando docker exec em cada container
```

Cada Moodle continua executando seu proprio cron, mas voce nao mantem um container extra permanentemente ligado para cada instituicao.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- entender o papel do cron no Moodle;
- diferenciar container permanente de comando executado sob demanda;
- usar `docker exec` para rodar comandos dentro de containers;
- listar containers em execucao;
- verificar logs de containers;
- criar scripts shell simples;
- tornar um script executavel;
- criar logs locais por instituicao;
- evitar execucoes simultaneas do mesmo cron;
- agendar comandos no host usando `crontab`;
- validar se o cron esta rodando corretamente;
- remover ou ignorar o servico `cron` antigo do Compose monolitico.

## Resultado esperado

Ao final deste passo:

- nao existira container permanente de cron para cada instituicao;
- o cron da `escola-a` sera executado dentro de `moodle_escola_a`;
- o cron da `escola-b` sera executado dentro de `moodle_escola_b`;
- as execucoes serao iniciadas pelo host com `docker exec`;
- cada instituicao tera log proprio em `logs/moodle-cron/`;
- sera possivel agendar as execucoes a cada minuto;
- as execucoes poderao ser distribuidas em segundos diferentes para reduzir picos.

## Pre-requisitos

Antes de iniciar este passo, conclua:

```text
docs/passo-03-infraestrutura-compartilhada.md
docs/passo-04-criar-bancos-e-usuarios.md
docs/passo-05-criar-servico-moodle-por-instituicao.md
docs/passo-06-configurar-redis-prefixos.md
```

Arquivos esperados:

```text
docker-compose.infra.yml
docker-compose.instituicoes.yml
secrets/escola-a.local.env
secrets/escola-b.local.env
```

Containers esperados:

```text
moodle_db
moodle_redis
moodle_proxy
moodle_escola_a
moodle_escola_b
```

Neste laboratorio local, vamos usar duas instituicoes:

```text
moodle_escola_a
moodle_escola_b
```

## Conceitos rapidos antes dos comandos

### O que e o cron do Moodle

O Moodle possui tarefas internas que precisam rodar regularmente.

Exemplos:

- envio de notificacoes;
- processamento de tarefas pendentes;
- limpeza de caches temporarios;
- processamento de arquivos;
- rotinas de cursos e atividades;
- tarefas agendadas de plugins.

Essas tarefas sao executadas pelo arquivo:

```text
/var/www/html/admin/cli/cron.php
```

Dentro de um container Moodle, o comando e:

```sh
php /var/www/html/admin/cli/cron.php
```

### Por que cada instituicao precisa do seu proprio cron

Cada instituicao tem:

- banco proprio;
- `moodledata` proprio;
- configuracoes proprias;
- fila de tarefas propria.

Por isso, o cron precisa ser executado dentro do container da propria instituicao.

Exemplo:

```sh
docker exec moodle_escola_a php /var/www/html/admin/cli/cron.php
docker exec moodle_escola_b php /var/www/html/admin/cli/cron.php
```

O primeiro comando carrega o `config.php` e as variaveis da escola A.

O segundo comando carrega o `config.php` e as variaveis da escola B.

### O que e `docker exec`

`docker exec` executa um comando dentro de um container que ja esta rodando.

Formato:

```sh
docker exec NOME_DO_CONTAINER COMANDO
```

Exemplo:

```sh
docker exec moodle_escola_a php -v
```

Esse comando nao cria um novo container. Ele entra no container existente `moodle_escola_a` e roda `php -v`.

### Por que nao criar um container de cron por instituicao

Criar um container de cron por instituicao funciona, mas aumenta a quantidade de processos permanentes.

Com 50 instituicoes, voce teria:

```text
50 containers Moodle
50 containers cron
```

Com agendamento central, voce mantem:

```text
50 containers Moodle
1 agendamento no host
```

O trabalho do cron continua existindo, mas ele roda somente quando e chamado.

## Etapa 1: Entrar na pasta do projeto

Execute:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

Confirme a pasta atual:

```sh
pwd
```

Resultado esperado:

```text
/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker
```

## Etapa 2: Verificar se o Docker esta funcionando

Execute:

```sh
docker version
```

Resultado esperado:

```text
Client:
 ...

Server:
 ...
```

Se aparecer erro de conexao com o Docker daemon, abra o Docker Desktop e aguarde ele iniciar.

Depois execute:

```sh
docker ps
```

Esse comando lista os containers em execucao.

## Etapa 3: Subir a infraestrutura compartilhada

Execute:

```sh
docker compose -f docker-compose.infra.yml up -d
```

O que esse comando faz:

- `docker compose`: usa o Docker Compose;
- `-f docker-compose.infra.yml`: escolhe o arquivo de infraestrutura;
- `up`: cria ou atualiza os containers;
- `-d`: roda em background.

Verifique os containers:

```sh
docker compose -f docker-compose.infra.yml ps
```

Resultado esperado:

```text
moodle_db       running
moodle_redis    running
moodle_proxy    running
```

Tambem confira diretamente pelo Docker:

```sh
docker ps --filter "name=moodle_"
```

## Etapa 4: Subir os containers das instituicoes

Execute:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

Verifique:

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

Resultado esperado:

```text
moodle_escola_a    running
moodle_escola_b    running
```

Tambem confira:

```sh
docker ps --filter "name=moodle_escola"
```

## Etapa 5: Confirmar que nao existe cron por instituicao no Compose novo

Execute:

```sh
docker compose -f docker-compose.instituicoes.yml config --services
```

Resultado esperado:

```text
moodle_escola_a
moodle_escola_b
```

Nao deve aparecer:

```text
cron_escola_a
cron_escola_b
moodle_cron
```

Se aparecer algum servico de cron no Compose de instituicoes, remova-o antes de seguir.

## Etapa 6: Entender o cron antigo do projeto

O arquivo antigo `docker-compose.yml` ainda possui um servico chamado:

```text
cron
```

Esse servico era adequado para o laboratorio de instancia unica, mas nao e o modelo recomendado para varias instituicoes.

Para visualizar os servicos do Compose antigo, execute:

```sh
docker compose -f docker-compose.yml config --services
```

Resultado esperado no Compose antigo:

```text
db
moodle
cron
```

Neste passo, o arquivo principal para as instituicoes e:

```text
docker-compose.instituicoes.yml
```

O servico `cron` do `docker-compose.yml` antigo nao sera usado na arquitetura multi-instituicao.

## Etapa 7: Parar o cron antigo, se ele estiver rodando

Verifique se existe um container antigo chamado `moodle_cron`:

```sh
docker ps --filter "name=moodle_cron"
```

Se ele aparecer como `running`, pare o servico:

```sh
docker compose -f docker-compose.yml stop cron
```

Verifique novamente:

```sh
docker ps --filter "name=moodle_cron"
```

Se quiser remover apenas o container parado do cron antigo, execute:

```sh
docker compose -f docker-compose.yml rm -f cron
```

Observacao:

- `stop` para o container;
- `rm -f` remove o container parado;
- os volumes de dados nao sao apagados por esse comando.

Nao execute comandos de remocao de volumes neste passo.

## Etapa 8: Testar o cron manualmente na escola A

Execute:

```sh
docker exec moodle_escola_a php /var/www/html/admin/cli/cron.php
```

Resultado esperado:

```text
Server Time: ...
Execute scheduled task: ...
Cron script completed correctly
```

Se o Moodle ainda nao foi instalado no navegador, o comando pode falhar porque as tabelas do banco ainda nao existem.

Nesse caso:

1. acesse o Moodle da instituicao;
2. conclua a instalacao inicial;
3. execute novamente o cron.

Para ver os logs do container da escola A:

```sh
docker logs --tail=80 moodle_escola_a
```

## Etapa 9: Testar o cron manualmente na escola B

Execute:

```sh
docker exec moodle_escola_b php /var/www/html/admin/cli/cron.php
```

Resultado esperado:

```text
Server Time: ...
Execute scheduled task: ...
Cron script completed correctly
```

Verifique logs da escola B:

```sh
docker logs --tail=80 moodle_escola_b
```

## Etapa 10: Executar o cron como usuario `www-data`

Em containers PHP/Apache, o usuario do servidor web normalmente e `www-data`.

Para evitar arquivos gerados pelo cron com dono incorreto, prefira executar o cron como `www-data`.

Teste na escola A:

```sh
docker exec -u www-data moodle_escola_a php /var/www/html/admin/cli/cron.php
```

Teste na escola B:

```sh
docker exec -u www-data moodle_escola_b php /var/www/html/admin/cli/cron.php
```

Se funcionar, use `-u www-data` no script central.

## Etapa 11: Criar a pasta de scripts e logs

Crie as pastas:

```sh
mkdir -p scripts
mkdir -p logs/moodle-cron
```

Verifique:

```sh
ls -la scripts
ls -la logs
```

Resultado esperado:

```text
scripts
logs/moodle-cron
```

## Etapa 12: Criar o script central de cron

Crie o arquivo:

```sh
nano scripts/run-moodle-crons.sh
```

Cole o conteudo abaixo:

```sh
#!/usr/bin/env sh

set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs/moodle-cron"
LOCK_ROOT="${TMPDIR:-/tmp}/moodle-cron-locks"
DEFAULT_TENANTS="moodle_escola_a moodle_escola_b"

mkdir -p "$LOG_DIR"
mkdir -p "$LOCK_ROOT"

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_line() {
  tenant="$1"
  message="$2"
  printf "[%s] %s\n" "$(timestamp)" "$message" >> "$LOG_DIR/$tenant.log"
}

run_tenant_cron() {
  tenant="$1"
  lock_dir="$LOCK_ROOT/$tenant.lock"

  if ! docker inspect "$tenant" >/dev/null 2>&1; then
    log_line "$tenant" "SKIP: container nao existe"
    return 0
  fi

  running="$(docker inspect --format '{{.State.Running}}' "$tenant" 2>/dev/null || printf "false")"

  if [ "$running" != "true" ]; then
    log_line "$tenant" "SKIP: container nao esta em execucao"
    return 0
  fi

  if ! mkdir "$lock_dir" 2>/dev/null; then
    log_line "$tenant" "SKIP: cron anterior ainda esta em execucao"
    return 0
  fi

  log_line "$tenant" "START: executando cron"

  docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php >> "$LOG_DIR/$tenant.log" 2>&1
  status="$?"

  if [ "$status" -eq 0 ]; then
    log_line "$tenant" "OK: cron finalizado com sucesso"
  else
    log_line "$tenant" "ERROR: cron finalizado com status $status"
  fi

  rmdir "$lock_dir" 2>/dev/null || true

  return "$status"
}

if [ "$#" -gt 0 ]; then
  TENANTS="$*"
else
  TENANTS="${MOODLE_CRON_TENANTS:-$DEFAULT_TENANTS}"
fi

FINAL_STATUS=0

for tenant in $TENANTS; do
  run_tenant_cron "$tenant" || FINAL_STATUS=1
done

exit "$FINAL_STATUS"
```

Salve o arquivo.

No `nano`:

```text
Ctrl + O
Enter
Ctrl + X
```

## Etapa 13: Tornar o script executavel

Execute:

```sh
chmod +x scripts/run-moodle-crons.sh
```

Verifique:

```sh
ls -la scripts/run-moodle-crons.sh
```

Resultado esperado:

```text
-rwxr-xr-x ... scripts/run-moodle-crons.sh
```

O `x` indica que o arquivo pode ser executado.

## Etapa 14: Executar o script para todas as instituicoes

Execute:

```sh
./scripts/run-moodle-crons.sh
```

Esse comando executa o cron para:

```text
moodle_escola_a
moodle_escola_b
```

Verifique os logs:

```sh
ls -la logs/moodle-cron
```

Resultado esperado:

```text
moodle_escola_a.log
moodle_escola_b.log
```

Leia o log da escola A:

```sh
tail -n 80 logs/moodle-cron/moodle_escola_a.log
```

Leia o log da escola B:

```sh
tail -n 80 logs/moodle-cron/moodle_escola_b.log
```

Procure por linhas parecidas com:

```text
START: executando cron
OK: cron finalizado com sucesso
```

## Etapa 15: Executar o script para uma unica instituicao

Execute somente a escola A:

```sh
./scripts/run-moodle-crons.sh moodle_escola_a
```

Execute somente a escola B:

```sh
./scripts/run-moodle-crons.sh moodle_escola_b
```

Isso e util para:

- testar uma instituicao especifica;
- investigar erro isolado;
- distribuir execucoes em horarios diferentes.

## Etapa 16: Testar o controle contra execucao duplicada

O script usa uma pasta de lock por instituicao em:

```text
/tmp/moodle-cron-locks
```

Isso evita que dois crons da mesma instituicao rodem ao mesmo tempo.

Para simular um lock da escola A, execute:

```sh
mkdir -p /tmp/moodle-cron-locks/moodle_escola_a.lock
```

Agora execute:

```sh
./scripts/run-moodle-crons.sh moodle_escola_a
```

Verifique o log:

```sh
tail -n 20 logs/moodle-cron/moodle_escola_a.log
```

Resultado esperado:

```text
SKIP: cron anterior ainda esta em execucao
```

Remova o lock de teste:

```sh
rmdir /tmp/moodle-cron-locks/moodle_escola_a.lock
```

Execute novamente:

```sh
./scripts/run-moodle-crons.sh moodle_escola_a
```

Agora o cron deve rodar normalmente.

## Etapa 17: Agendar com crontab do host

Nesta etapa, o host sera responsavel por chamar o script.

No macOS e em Linux, voce pode usar `crontab`.

Abra o editor do crontab:

```sh
crontab -e
```

Adicione estas linhas:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a
* * * * * sleep 15; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_b
```

Salve e feche o editor.

O que essas linhas fazem:

- a escola A roda no inicio de cada minuto;
- a escola B roda 15 segundos depois;
- os crons nao iniciam exatamente ao mesmo tempo;
- cada comando entra na pasta do projeto antes de chamar o script.

## Etapa 18: Verificar se o crontab foi salvo

Execute:

```sh
crontab -l
```

Resultado esperado:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a
* * * * * sleep 15; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_b
```

## Etapa 19: Aguardar e validar execucao automatica

Aguarde pelo menos 2 minutos.

Depois execute:

```sh
tail -n 40 logs/moodle-cron/moodle_escola_a.log
```

E:

```sh
tail -n 40 logs/moodle-cron/moodle_escola_b.log
```

Voce deve ver execucoes recentes com horario atualizado.

Para acompanhar em tempo real:

```sh
tail -f logs/moodle-cron/moodle_escola_a.log
```

Em outro terminal:

```sh
tail -f logs/moodle-cron/moodle_escola_b.log
```

Para parar o `tail -f`, pressione:

```text
Ctrl + C
```

## Etapa 20: Validar pelo painel do Moodle

Acesse a escola A no navegador e entre como administrador.

Depois navegue ate:

```text
Administracao do site > Servidor > Tarefas > Tarefas agendadas
```

Verifique se as tarefas estao com datas recentes de ultima execucao.

Repita na escola B.

Se as datas nao atualizarem:

- confira se o crontab esta instalado;
- confira se Docker Desktop esta aberto;
- confira os logs em `logs/moodle-cron/`;
- rode o script manualmente para comparar.

## Etapa 21: Verificar containers durante a execucao

Liste os containers:

```sh
docker ps --filter "name=moodle_escola"
```

Durante o cron, voce nao deve ver containers novos sendo criados.

O esperado e continuar vendo apenas:

```text
moodle_escola_a
moodle_escola_b
```

Isso confirma que o modelo usa `docker exec` dentro dos containers existentes.

## Etapa 22: Verificar consumo basico

Execute:

```sh
docker stats --no-stream moodle_escola_a moodle_escola_b moodle_db moodle_redis
```

Esse comando mostra um snapshot de:

- CPU;
- memoria;
- rede;
- I/O de bloco;
- quantidade de processos.

Use esse comando antes e depois do cron para observar o impacto.

## Etapa 23: Adicionar uma nova instituicao ao script

Quando existir uma nova instituicao, por exemplo:

```text
moodle_escola_c
```

Voce tem duas opcoes.

Opcao 1: passar o container diretamente no crontab:

```cron
* * * * * sleep 30; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_c
```

Opcao 2: editar o script e adicionar no valor padrao:

```sh
nano scripts/run-moodle-crons.sh
```

Alterar:

```sh
DEFAULT_TENANTS="moodle_escola_a moodle_escola_b"
```

Para:

```sh
DEFAULT_TENANTS="moodle_escola_a moodle_escola_b moodle_escola_c"
```

Depois teste:

```sh
./scripts/run-moodle-crons.sh moodle_escola_c
```

## Etapa 24: Distribuir execucoes quando houver mais instituicoes

Para poucas instituicoes, usar `sleep` no crontab e suficiente.

Exemplo com quatro instituicoes:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a
* * * * * sleep 15; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_b
* * * * * sleep 30; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_c
* * * * * sleep 45; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_d
```

Para muitas instituicoes, agrupe por blocos:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a moodle_escola_b moodle_escola_c
* * * * * sleep 20; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_d moodle_escola_e moodle_escola_f
* * * * * sleep 40; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_g moodle_escola_h moodle_escola_i
```

Regra pratica:

- nao inicie todos os crons ao mesmo tempo;
- evite concorrencia alta no banco;
- monitore tempo de execucao;
- se uma instituicao demora muito, coloque ela em uma janela separada.

## Etapa 25: Remover o agendamento local

Se quiser parar o agendamento automatico local, execute:

```sh
crontab -e
```

Remova as linhas relacionadas ao Moodle:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a
* * * * * sleep 15; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_b
```

Salve e verifique:

```sh
crontab -l
```

## Etapa 26: Troubleshooting

### Erro: `Cannot connect to the Docker daemon`

Significa que o Docker Desktop provavelmente nao esta aberto.

Verifique:

```sh
docker ps
```

Se falhar, abra o Docker Desktop e tente novamente.

### Erro: `No such container: moodle_escola_a`

O container nao existe ou esta com outro nome.

Liste os containers:

```sh
docker ps -a --filter "name=moodle"
```

Suba as instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

### Erro: container existe, mas nao esta rodando

Verifique:

```sh
docker ps -a --filter "name=moodle_escola_a"
```

Suba novamente:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_a
```

Veja logs:

```sh
docker logs --tail=120 moodle_escola_a
```

### Erro: `Could not open input file: /var/www/html/admin/cli/cron.php`

O caminho do Moodle dentro da imagem pode estar diferente ou a imagem nao foi construida corretamente.

Verifique os arquivos dentro do container:

```sh
docker exec moodle_escola_a ls -la /var/www/html/admin/cli
```

Verifique a imagem usada:

```sh
docker inspect moodle_escola_a --format '{{.Config.Image}}'
```

### Erro: `Database connection failed`

O cron carrega o mesmo `config.php` do Moodle.

Verifique as variaveis da escola A:

```sh
docker exec moodle_escola_a printenv MOODLE_DB_HOST
docker exec moodle_escola_a printenv MOODLE_DB_NAME
docker exec moodle_escola_a printenv MOODLE_DB_USER
```

Verifique se o banco esta rodando:

```sh
docker ps --filter "name=moodle_db"
```

Veja logs do banco:

```sh
docker logs --tail=120 moodle_db
```

### O cron manual funciona, mas o crontab nao

Esse e um problema comum.

Possiveis causas:

- Docker CLI nao esta no `PATH` do cron;
- Docker Desktop nao esta aberto;
- caminho do projeto esta errado;
- script nao esta executavel;
- crontab foi salvo no usuario errado.

Valide:

```sh
which docker
```

Verifique permissao:

```sh
ls -la scripts/run-moodle-crons.sh
```

Execute com caminho completo:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
./scripts/run-moodle-crons.sh moodle_escola_a
```

Veja os logs:

```sh
tail -n 120 logs/moodle-cron/moodle_escola_a.log
```

### Log mostra `SKIP: cron anterior ainda esta em execucao`

Pode ser uma execucao real ainda em andamento, ou um lock antigo deixado por interrupcao.

Veja os locks:

```sh
ls -la /tmp/moodle-cron-locks
```

Se voce tem certeza de que nao ha cron rodando, remova o lock especifico:

```sh
rmdir /tmp/moodle-cron-locks/moodle_escola_a.lock
```

Depois teste:

```sh
./scripts/run-moodle-crons.sh moodle_escola_a
```

## Checklist de conclusao

Marque cada item ao concluir:

- [ ] Entrei na pasta do projeto.
- [ ] Subi `docker-compose.infra.yml`.
- [ ] Subi `docker-compose.instituicoes.yml`.
- [ ] Confirmei que `moodle_escola_a` esta rodando.
- [ ] Confirmei que `moodle_escola_b` esta rodando.
- [ ] Confirmei que nao existe cron no Compose de instituicoes.
- [ ] Parei o `moodle_cron` antigo, se ele estava rodando.
- [ ] Executei o cron manual da escola A.
- [ ] Executei o cron manual da escola B.
- [ ] Criei `scripts/run-moodle-crons.sh`.
- [ ] Tornei o script executavel.
- [ ] Rodei o script para todas as instituicoes.
- [ ] Verifiquei logs em `logs/moodle-cron/`.
- [ ] Configurei o `crontab`.
- [ ] Aguardei pelo menos 2 minutos.
- [ ] Confirmei execucoes automaticas nos logs.
- [ ] Validei no painel do Moodle.

## Resumo operacional

Comando manual por instituicao:

```sh
docker exec -u www-data moodle_escola_a php /var/www/html/admin/cli/cron.php
```

Comando central por script:

```sh
./scripts/run-moodle-crons.sh moodle_escola_a moodle_escola_b
```

Agendamento local:

```cron
* * * * * cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_a
* * * * * sleep 15; cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker" && ./scripts/run-moodle-crons.sh moodle_escola_b
```

Arquivos criados neste passo:

```text
scripts/run-moodle-crons.sh
logs/moodle-cron/moodle_escola_a.log
logs/moodle-cron/moodle_escola_b.log
```

Modelo final:

```text
Host crontab
  |
  +-- docker exec moodle_escola_a php /var/www/html/admin/cli/cron.php
  |
  +-- sleep 15
      |
      +-- docker exec moodle_escola_b php /var/www/html/admin/cli/cron.php
```

