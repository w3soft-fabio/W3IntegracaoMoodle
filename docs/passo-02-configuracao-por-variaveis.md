# Passo 2: Transformar `config.php` em configuracao por variaveis

## Objetivo deste passo

Neste passo, o objetivo e remover valores fixos do arquivo `moodle/config.php` e fazer o Moodle ler suas configuracoes a partir de variaveis de ambiente.

Hoje o projeto possui uma unica instalacao Moodle com configuracoes fixas:

```php
$CFG->dbhost    = 'db';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodle';
$CFG->dbpass    = 'moodlepass';
$CFG->wwwroot   = 'http://localhost:8080';
$CFG->dataroot  = '/var/www/moodledata';
```

Isso funciona para uma instalacao local unica, mas nao escala bem para varias instituicoes. No modelo recomendado, todas as instituicoes podem usar a mesma imagem Docker do Moodle, mas cada container recebe valores diferentes por ambiente.

Exemplo futuro:

```text
moodle_escola_a
  MOODLE_URL=http://localhost:8081
  MOODLE_DB_NAME=moodle_escola_a
  MOODLE_DB_USER=moodle_escola_a
  MOODLE_DATAROOT=/var/www/moodledata

moodle_escola_b
  MOODLE_URL=http://localhost:8082
  MOODLE_DB_NAME=moodle_escola_b
  MOODLE_DB_USER=moodle_escola_b
  MOODLE_DATAROOT=/var/www/moodledata
```

A imagem continua igual. O que muda e a configuracao recebida por cada container.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- entender variaveis de ambiente em containers;
- criar um arquivo de ambiente para Docker Compose;
- passar variaveis para servicos com `env_file`;
- diferenciar valores da imagem e valores do container;
- alterar `config.php` para ler `getenv()`;
- reconstruir uma imagem apos alterar arquivos copiados pelo Dockerfile;
- validar a configuracao final do Compose;
- acessar variaveis dentro de um container com `docker compose exec`;
- verificar logs de containers;
- aplicar rollback simples caso a configuracao falhe.

## Conceitos rapidos antes dos comandos

### Variavel de ambiente

Uma variavel de ambiente e um par nome/valor disponivel dentro de um processo.

Exemplo:

```text
MOODLE_DB_NAME=moodle
```

Dentro do PHP, o Moodle pode ler esse valor com:

```php
getenv('MOODLE_DB_NAME')
```

### `env_file`

No Docker Compose, `env_file` e uma forma de carregar varias variaveis de ambiente a partir de um arquivo.

Exemplo:

```yaml
services:
  moodle:
    env_file:
      - ./secrets/local.env
```

Isso faz com que as variaveis de `secrets/local.env` fiquem disponiveis dentro do container `moodle`.

### Por que nao deixar tudo fixo no `config.php`

Se `config.php` tiver tudo fixo, cada instituicao precisaria de uma imagem ou arquivo diferente.

Se `config.php` ler variaveis, a mesma imagem pode atender varios containers:

```text
Mesma imagem:
  w3soft/moodle:2026.06.1-local

Containers diferentes:
  moodle_app
  moodle_escola_a
  moodle_escola_b
```

Cada container recebe seu proprio conjunto de variaveis.

## Decisao tecnica deste passo

Neste passo, vamos manter a arquitetura atual com uma unica instituicao local:

- container `db`;
- container `moodle`;
- container `cron`;
- banco `moodle`;
- usuario `moodle`;
- senha `moodlepass`;
- URL `http://localhost:8080`.

A mudanca sera apenas tornar esses valores configuraveis por variaveis de ambiente.

Isso e proposital. A ideia e aprender e validar uma mudanca de cada vez.

## Estrutura atual relevante

Arquivos envolvidos diretamente:

```text
docker-compose.yml
moodle/config.php
```

Arquivos que serao criados:

```text
secrets/local.env
docs/passo-02-configuracao-por-variaveis.md
```

Opcionalmente, se o projeto estiver usando Git, tambem sera ajustado:

```text
.gitignore
```

## Etapa 1: Entrar na pasta do projeto

Execute:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

Confirme que voce esta na pasta correta:

```sh
pwd
```

Resultado esperado:

```text
/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker
```

Liste os arquivos:

```sh
ls
```

Resultado esperado, no minimo:

```text
docker-compose.yml
docs
moodle
```

## Etapa 2: Ver a configuracao atual do Moodle

Execute:

```sh
sed -n '1,220p' moodle/config.php
```

Voce deve encontrar algo parecido com:

```php
$CFG->dbhost    = 'db';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodle';
$CFG->dbpass    = 'moodlepass';
$CFG->wwwroot   = 'http://localhost:8080';
$CFG->dataroot  = '/var/www/moodledata';
```

Esses sao os valores que vamos mover para variaveis de ambiente.

## Etapa 3: Criar um backup local do `config.php`

Antes de alterar o arquivo, crie uma copia de seguranca:

```sh
cp moodle/config.php moodle/config.php.bak-passo-02
```

Confira se o backup foi criado:

```sh
ls moodle/config.php*
```

Resultado esperado:

```text
moodle/config.php
moodle/config.php.bak-passo-02
```

Esse backup facilita voltar rapidamente se algo for digitado errado.

## Etapa 4: Criar a pasta de secrets

Crie uma pasta para arquivos de ambiente locais:

```sh
mkdir -p secrets
```

Confirme:

```sh
ls
```

Agora deve existir tambem:

```text
secrets
```

## Etapa 5: Criar o arquivo `secrets/local.env`

Crie o arquivo:

```sh
touch secrets/local.env
```

Abra o arquivo em um editor. Se voce usa VS Code:

```sh
code secrets/local.env
```

Se preferir terminal:

```sh
nano secrets/local.env
```

Cole este conteudo:

```env
MOODLE_URL=http://localhost:8080
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=moodle
MOODLE_DB_PASSWORD=moodlepass
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=local
MOODLE_TENANT_ID=local-dev
```

Salve o arquivo.

Se estiver usando `nano`:

1. pressione `Ctrl + O`;
2. pressione `Enter`;
3. pressione `Ctrl + X`.

## Etapa 6: Entender cada variavel criada

As variaveis possuem estas funcoes:

```text
MOODLE_URL
```

URL publica do Moodle. Localmente, continua sendo `http://localhost:8080`.

```text
MOODLE_DB_HOST
```

Nome do host do banco dentro da rede Docker. No Compose atual, o servico do banco se chama `db`, entao os containers Moodle acessam o banco pelo nome `db`.

```text
MOODLE_DB_NAME
```

Nome do banco usado pelo Moodle. Neste passo, continua sendo `moodle`.

```text
MOODLE_DB_USER
```

Usuario do banco. Neste passo, continua sendo `moodle`.

```text
MOODLE_DB_PASSWORD
```

Senha do usuario do banco. Neste passo, continua sendo `moodlepass`.

```text
MOODLE_DATAROOT
```

Caminho interno do container onde o Moodle guarda arquivos enviados, cache local e outros dados. Neste projeto, o volume e montado em `/var/www/moodledata`.

```text
MOODLE_PUBLIC_SLUG
```

Identificador publico amigavel da instituicao. Neste passo usamos `local`, mas futuramente poderia ser `escola-a`.

```text
MOODLE_TENANT_ID
```

Identificador tecnico interno. Neste passo usamos `local-dev`. Futuramente, esse valor deve ser imutavel por instituicao.

## Etapa 7: Proteger o arquivo de secrets local

Em ambiente real, arquivos de secrets nao devem ser acessiveis por qualquer usuario da maquina.

Localmente, ajuste a permissao:

```sh
chmod 600 secrets/local.env
```

Confira:

```sh
ls -l secrets/local.env
```

Resultado esperado no comeco da linha:

```text
-rw-------
```

## Etapa 8: Evitar versionar secrets

Se o projeto estiver usando Git, confira se existe `.git`:

```sh
ls -a
```

Se aparecer `.git`, crie ou edite o `.gitignore`:

```sh
touch .gitignore
```

Abra:

```sh
code .gitignore
```

ou:

```sh
nano .gitignore
```

Adicione:

```gitignore
secrets/*.env
```

Depois confira:

```sh
sed -n '1,120p' .gitignore
```

Observacao: mesmo em ambiente local, e uma boa pratica nao versionar arquivos com senhas.

## Etapa 9: Alterar o `config.php`

Abra o arquivo:

```sh
code moodle/config.php
```

ou:

```sh
nano moodle/config.php
```

Substitua todo o conteudo por este:

```php
<?php

unset($CFG);
global $CFG;
$CFG = new stdClass();

function moodle_env_required(string $name): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        throw new RuntimeException("Missing required environment variable: {$name}");
    }

    return $value;
}

function moodle_env_optional(string $name, string $default): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return $value;
}

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = moodle_env_optional('MOODLE_DB_HOST', 'db');
$CFG->dbname    = moodle_env_required('MOODLE_DB_NAME');
$CFG->dbuser    = moodle_env_required('MOODLE_DB_USER');
$CFG->dbpass    = moodle_env_required('MOODLE_DB_PASSWORD');
$CFG->prefix    = 'mdl_';

$CFG->dboptions = [
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
];

$CFG->wwwroot   = moodle_env_required('MOODLE_URL');
$CFG->dataroot  = moodle_env_optional('MOODLE_DATAROOT', '/var/www/moodledata');
$CFG->admin     = 'admin';

$publicSlug = getenv('MOODLE_PUBLIC_SLUG');

if ($publicSlug !== false && $publicSlug !== '') {
    $sessionSlug = preg_replace('/[^a-zA-Z0-9_]/', '_', $publicSlug);
    $CFG->sessioncookie = 'MoodleSession_' . $sessionSlug;
}

$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');
```

Salve o arquivo.

## Etapa 10: Entender o novo `config.php`

Esta funcao exige que a variavel exista:

```php
function moodle_env_required(string $name): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        throw new RuntimeException("Missing required environment variable: {$name}");
    }

    return $value;
}
```

Ela sera usada para valores sem os quais o Moodle nao deve iniciar, como:

```php
$CFG->dbname = moodle_env_required('MOODLE_DB_NAME');
```

Esta outra funcao permite um valor padrao:

```php
function moodle_env_optional(string $name, string $default): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return $value;
}
```

Ela e usada em configuracoes que podem ter padrao local:

```php
$CFG->dbhost = moodle_env_optional('MOODLE_DB_HOST', 'db');
```

O trecho abaixo cria um nome de cookie diferente por instituicao:

```php
$publicSlug = getenv('MOODLE_PUBLIC_SLUG');

if ($publicSlug !== false && $publicSlug !== '') {
    $sessionSlug = preg_replace('/[^a-zA-Z0-9_]/', '_', $publicSlug);
    $CFG->sessioncookie = 'MoodleSession_' . $sessionSlug;
}
```

Isso ajuda no futuro quando existirem varios Moodles no mesmo navegador.

## Etapa 11: Validar a sintaxe do PHP usando Docker

Como o PHP esta dentro da imagem Docker, podemos validar o arquivo com um container temporario.

Execute:

```sh
docker compose run --rm --no-deps moodle php -l /var/www/html/config.php
```

Resultado esperado:

```text
No syntax errors detected in /var/www/html/config.php
```

Se aparecer erro de sintaxe, revise o arquivo `moodle/config.php`, corrija e execute o comando novamente.

## Etapa 12: Alterar o `docker-compose.yml`

Agora precisamos fazer os servicos `moodle` e `cron` receberem o arquivo `secrets/local.env`.

Abra:

```sh
code docker-compose.yml
```

ou:

```sh
nano docker-compose.yml
```

No servico `moodle`, adicione:

```yaml
    env_file:
      - ./secrets/local.env
```

O servico `moodle` deve ficar parecido com:

```yaml
  moodle:
    image: w3soft/moodle:2026.06.1-local
    build:
      context: ./moodle
    container_name: moodle_app
    restart: unless-stopped
    env_file:
      - ./secrets/local.env
    ports:
      - "8080:80"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - moodledata:/var/www/moodledata
    networks:
      - moodle_net
```

No servico `cron`, adicione o mesmo `env_file`:

```yaml
    env_file:
      - ./secrets/local.env
```

O servico `cron` deve ficar parecido com:

```yaml
  cron:
    image: w3soft/moodle:2026.06.1-local
    container_name: moodle_cron
    restart: unless-stopped
    env_file:
      - ./secrets/local.env
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - moodledata:/var/www/moodledata
    command: >
      sh -c "while true; do php /var/www/html/admin/cli/cron.php; sleep 60; done"
    networks:
      - moodle_net
```

Importante: o `cron` tambem precisa das variaveis porque ele executa scripts PHP do Moodle e tambem carrega o `config.php`.

## Etapa 13: Validar o Compose

Execute:

```sh
docker compose config
```

Esse comando monta a configuracao final e mostra se o YAML esta valido.

Voce deve ver os servicos:

```text
db
moodle
cron
```

E deve ver o `env_file` nos servicos `moodle` e `cron`.

Se aparecer erro de identacao, revise os espacos no `docker-compose.yml`. YAML depende muito de identacao correta.

## Etapa 14: Reconstruir a imagem

O `Dockerfile` copia `moodle/config.php` para dentro da imagem:

```dockerfile
COPY config.php /var/www/html/config.php
```

Por isso, depois de alterar `moodle/config.php`, voce precisa reconstruir a imagem.

Execute:

```sh
docker compose build moodle
```

Resultado esperado: o Docker deve construir novamente a imagem `w3soft/moodle:2026.06.1-local`.

Se quiser forcar rebuild sem cache:

```sh
docker compose build --no-cache moodle
```

Normalmente, `docker compose build moodle` ja e suficiente durante o aprendizado.

## Etapa 15: Subir os containers

Execute:

```sh
docker compose up -d
```

Esse comando sobe os containers em segundo plano.

Confira o status:

```sh
docker compose ps
```

Resultado esperado:

```text
NAME          SERVICE   STATUS
moodle_db     db        running
moodle_app    moodle    running
moodle_cron   cron      running
```

Os textos exatos podem variar, mas os tres servicos devem estar em execucao.

## Etapa 16: Verificar se as variaveis chegaram no container

Execute:

```sh
docker compose exec moodle printenv MOODLE_URL
```

Resultado esperado:

```text
http://localhost:8080
```

Confira o nome do banco:

```sh
docker compose exec moodle printenv MOODLE_DB_NAME
```

Resultado esperado:

```text
moodle
```

Confira tambem no container de cron:

```sh
docker compose exec cron printenv MOODLE_DB_NAME
```

Resultado esperado:

```text
moodle
```

Se uma dessas variaveis aparecer vazia, o `env_file` provavelmente nao foi adicionado corretamente ou o caminho do arquivo esta errado.

## Etapa 17: Verificar logs do Moodle

Veja os logs do container web:

```sh
docker compose logs --tail=80 moodle
```

Procure erros relacionados a:

```text
Missing required environment variable
```

Se esse erro aparecer, significa que alguma variavel obrigatoria nao chegou ao container.

Veja tambem os logs do cron:

```sh
docker compose logs --tail=80 cron
```

O cron tambem carrega o `config.php`, entao erros de configuracao podem aparecer nele.

## Etapa 18: Acessar o Moodle pelo navegador

Abra:

```text
http://localhost:8080
```

Resultado esperado:

- o Moodle deve abrir normalmente;
- se ja estava instalado, deve continuar acessando o mesmo banco e o mesmo `moodledata`;
- se ainda nao estava instalado, deve iniciar o fluxo normal de instalacao.

## Etapa 19: Verificar se o Moodle esta usando o banco correto

Entre no container do banco:

```sh
docker compose exec db mariadb -umoodle -pmoodlepass moodle
```

Dentro do console do MariaDB, execute:

```sql
SHOW TABLES;
```

Se o Moodle ja foi instalado, voce deve ver varias tabelas com prefixo:

```text
mdl_
```

Para sair:

```sql
exit;
```

Esse teste confirma que as variaveis ainda apontam para o mesmo banco local.

## Etapa 20: Testar falha controlada de variavel obrigatoria

Esta etapa e opcional, mas ajuda a aprender.

Pare os containers:

```sh
docker compose down
```

Abra o arquivo:

```sh
nano secrets/local.env
```

Comente temporariamente a linha:

```env
# MOODLE_DB_NAME=moodle
```

Suba novamente:

```sh
docker compose up -d
```

Veja os logs:

```sh
docker compose logs --tail=80 moodle
```

Resultado esperado: o Moodle deve reclamar que a variavel obrigatoria esta ausente.

Depois descomente a linha:

```env
MOODLE_DB_NAME=moodle
```

Suba novamente:

```sh
docker compose up -d
```

Essa etapa mostra por que a funcao `moodle_env_required()` e util: ela falha cedo quando uma configuracao essencial esta faltando.

## Etapa 21: Comandos uteis para diagnostico

Ver containers em execucao:

```sh
docker compose ps
```

Ver logs do Moodle:

```sh
docker compose logs -f moodle
```

Ver logs do banco:

```sh
docker compose logs -f db
```

Ver logs do cron:

```sh
docker compose logs -f cron
```

Entrar no container Moodle:

```sh
docker compose exec moodle sh
```

Sair do shell do container:

```sh
exit
```

Listar variaveis que comecam com `MOODLE_` dentro do container:

```sh
docker compose exec moodle sh -c 'printenv | grep ^MOODLE_'
```

Validar sintaxe do PHP:

```sh
docker compose exec moodle php -l /var/www/html/config.php
```

Ver a configuracao final do Compose:

```sh
docker compose config
```

Parar containers sem apagar volumes:

```sh
docker compose down
```

Subir containers novamente:

```sh
docker compose up -d
```

Reconstruir imagem apos mudar arquivos em `moodle/`:

```sh
docker compose build moodle
```

## Etapa 22: Rollback se algo der errado

Se o Moodle nao subir e voce quiser voltar rapidamente ao estado anterior, restaure o backup:

```sh
cp moodle/config.php.bak-passo-02 moodle/config.php
```

Remova temporariamente o `env_file` dos servicos `moodle` e `cron` no `docker-compose.yml`, ou deixe-o sem uso.

Reconstrua a imagem:

```sh
docker compose build moodle
```

Suba novamente:

```sh
docker compose up -d
```

Veja os logs:

```sh
docker compose logs --tail=80 moodle
```

Esse rollback nao apaga banco nem `moodledata`.

## Etapa 23: Como este passo prepara a multi-instituicao

Depois deste passo, o `config.php` deixa de ser especifico de uma unica escola.

Isso permite criar varios containers Moodle com a mesma imagem, mudando apenas as variaveis.

Exemplo futuro:

```text
secrets/escola-a.env
secrets/escola-b.env
secrets/escola-c.env
```

Cada arquivo poderia conter:

```env
MOODLE_URL=http://localhost:8081
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-da-escola-a
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola-a
MOODLE_TENANT_ID=tenant-001
```

E o Compose poderia ter:

```yaml
services:
  moodle_escola_a:
    image: w3soft/moodle:2026.06.1-local
    env_file:
      - ./secrets/escola-a.env
    volumes:
      - moodledata_escola_a:/var/www/moodledata

  moodle_escola_b:
    image: w3soft/moodle:2026.06.1-local
    env_file:
      - ./secrets/escola-b.env
    volumes:
      - moodledata_escola_b:/var/www/moodledata
```

Esse e o ponto central da arquitetura:

```text
Uma imagem Moodle padronizada
+ varios containers
+ variaveis diferentes
+ bancos diferentes
+ volumes diferentes
```

## Checklist de conclusao

Ao final deste passo, confirme:

- `secrets/local.env` existe;
- `secrets/local.env` contem as variaveis `MOODLE_*`;
- `moodle/config.php` usa `getenv()` por meio das funcoes auxiliares;
- `docker-compose.yml` possui `env_file` no servico `moodle`;
- `docker-compose.yml` possui `env_file` no servico `cron`;
- `docker compose config` executa sem erro;
- `docker compose build moodle` executa sem erro;
- `docker compose up -d` sobe os containers;
- `docker compose exec moodle printenv MOODLE_DB_NAME` retorna `moodle`;
- `http://localhost:8080` abre o Moodle.

## Resultado esperado

Depois deste passo, o projeto continua funcionando como antes para uma unica instalacao local, mas com uma diferenca importante: a configuracao do Moodle passa a vir de variaveis de ambiente.

Essa mudanca e pequena, mas e uma base essencial para os proximos passos da arquitetura multi-instituicao.

