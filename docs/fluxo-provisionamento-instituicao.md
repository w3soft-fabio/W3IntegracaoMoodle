# Fluxo de provisionamento de uma nova instituicao Moodle

Este documento explica o fluxo de criacao de uma nova instituicao a partir do script
`scripts/provision-institution.py`, usando `tmp/escola-i.json` como exemplo.

O objetivo e deixar claro o que acontece em cada camada:

- arquivos alterados no host;
- recursos criados ou atualizados no Docker;
- banco de dados MariaDB;
- inicializacao do Moodle dentro do container;
- configuracoes PHP/Moodle aplicadas depois que o container sobe;
- cron centralizado;
- validacao e diagnostico.

## Visao geral

O projeto usa uma arquitetura de uma instalacao Moodle por instituicao, mas com
infraestrutura compartilhada.

```text
Navegador
   |
   | http://localhost:8088/i/escola-i/
   v
Caddy compartilhado
   |
   | reverse_proxy para moodle_escola_i:80
   v
Container Moodle da instituicao
   |
   +--> banco moodle_escola_i no MariaDB compartilhado
   +--> volume moodledata_escola_i
   +--> Redis compartilhado com prefixo escola_i_
```

Componentes compartilhados:

- `moodle_db`: MariaDB unico para todos os bancos logicos Moodle.
- `moodle_redis`: Redis unico, separado por prefixo por instituicao.
- `moodle_proxy`: Caddy unico, responsavel por rotear cada `/i/{slug}`.
- `moodle_net`: rede Docker bridge compartilhada.
- imagem Docker `w3soft/moodle:2026.07.1-local`.

Componentes por instituicao:

- container `moodle_{slug_com_underscore}`;
- banco `moodle_{slug_com_underscore}`;
- usuario de banco com o mesmo nome do banco;
- arquivo `secrets/{slug}.local.env`;
- volume `moodledata_{slug_com_underscore}`;
- rota no Caddy para `/i/{slug}`;
- entrada no arquivo de cron centralizado.

Para `tmp/escola-i.json`, o slug e `escola-i`. O identificador tecnico usado em
nomes Docker e banco troca hifen por underline: `escola_i`.

Resultado esperado para esse JSON:

```text
slug publico:       escola-i
identificador:      escola_i
container:          moodle_escola_i
banco:              moodle_escola_i
usuario do banco:   moodle_escola_i
volume:             moodledata_escola_i
rota publica:       http://localhost:8088/i/escola-i/
secret local:       secrets/escola-i.local.env
prefixo Redis:      escola_i_
```

## Entrada do fluxo

O exemplo `tmp/escola-i.json` contem:

```json
{
  "displayName": "Escola I",
  "slug": "escola-i",
  "tenantId": "escola-i-local",
  "databasePassword": "senha-local-escola-i",
  "publicUrl": "http://localhost:8088/i/escola-i",
  "cpu": "1.0",
  "memoryLimit": "1.5g",
  "memoryReservation": "512m"
}
```

Campos obrigatorios validados pelo script:

- `displayName`: nome exibido no Moodle.
- `slug`: identificador publico da URL.
- `tenantId`: identificador interno do tenant.
- `databasePassword`: senha do usuario MariaDB da instituicao.
- `publicUrl`: URL publica completa do Moodle da instituicao.
- `cpu`: limite de CPU do container Moodle.
- `memoryLimit`: limite maximo de memoria do container.
- `memoryReservation`: reserva de memoria do container.

A validacao do `slug` exige este padrao:

```text
[a-z0-9][a-z0-9-]*[a-z0-9]
```

Isso significa:

- apenas letras minusculas, numeros e hifens;
- nao pode comecar com hifen;
- nao pode terminar com hifen.

Observacao: por causa dessa regex, um slug com apenas um caractere nao passa na
validacao atual, mesmo que seja letra ou numero. Exemplo: `a` nao passaria.

## Como executar

Somente preparar arquivos, sem Docker:

```sh
scripts/provision-institution.py tmp/escola-i.json
```

Simular o fluxo completo, sem escrever arquivos e sem executar Docker:

```sh
scripts/provision-institution.py tmp/escola-i.json --dry-run --apply-all
```

Fluxo completo:

```sh
scripts/provision-institution.py tmp/escola-i.json --apply-all
```

Flags importantes:

- `--dry-run`: imprime o que faria, mas nao grava arquivos nem executa Docker.
- `--create-db`: cria/atualiza banco e usuario da instituicao no MariaDB.
- `--rebuild-image`: reconstrui a imagem local `w3soft/moodle:2026.07.1-local`.
- `--up`: sobe o container da instituicao e reinicia o proxy.
- `--apply-all`: combina atualizacao de arquivos, banco, build da imagem e start.

No dry-run com `tmp/escola-i.json`, a sequencia planejada e:

```text
atualizar docker-compose.instituicoes.yml
atualizar proxy/Caddyfile.local
atualizar config/moodle-cron-tenants.txt
gerar secrets/escola-i.local.env
executar SQL no container moodle_db
buildar imagem w3soft/moodle:2026.07.1-local
subir servico moodle_escola_i
reiniciar proxy Caddy
```

## Fluxo do script Python

O arquivo central e `scripts/provision-institution.py`.

Constantes principais:

```text
ROOT                         raiz do projeto
COMPOSE_FILE                 docker-compose.instituicoes.yml
CADDY_FILE                   proxy/Caddyfile.local
CRON_TENANTS_FILE            config/moodle-cron-tenants.txt
SECRETS_DIR                  secrets
IMAGE_TAG                    w3soft/moodle:2026.07.1-local
```

Fluxo principal da funcao `main()`:

```text
1. ler argumentos de linha de comando
2. carregar e validar JSON
3. atualizar docker-compose.instituicoes.yml
4. atualizar proxy/Caddyfile.local
5. atualizar config/moodle-cron-tenants.txt
6. gerar/atualizar secrets/{slug}.local.env
7. se --create-db ou --apply-all: criar/atualizar banco
8. se --rebuild-image ou --apply-all: rebuildar imagem
9. se --up ou --apply-all: subir container e reiniciar proxy
10. imprimir resumo
```

O script e majoritariamente idempotente. Idempotente significa que a mesma
operacao pode ser executada varias vezes sem duplicar recursos ou corromper o
estado esperado. Por exemplo: se o servico ja existe no Compose, ele nao e
adicionado de novo.

## Transformacoes de nomes

O script usa duas transformacoes importantes.

`slug_to_identifier(slug)`:

```text
escola-i -> escola_i
```

Uso:

- nomes de containers;
- nomes de bancos;
- nomes de usuarios MariaDB;
- nomes de volumes;
- prefixo Redis.

`caddy_matcher(slug)`:

```text
escola-i -> @tenantescolai
```

O matcher do Caddy remove caracteres que nao sejam letras minusculas ou numeros
e adiciona o prefixo `@tenant`.

Uso:

- bloco `@tenantescolai path /i/escola-i/*`;
- bloco `handle @tenantescolai { reverse_proxy moodle_escola_i:80 }`.

## Arquivos lidos, criados ou modificados

### `tmp/escola-i.json`

Tipo: arquivo lido.

Funcao:

- fornece os dados da instituicao;
- define URL publica;
- define limites de recursos;
- define senha do banco da instituicao.

O script nao modifica esse arquivo.

### `docker-compose.instituicoes.yml`

Tipo: arquivo modificado.

Funcao:

- declara os containers Moodle de cada instituicao;
- declara os volumes `moodledata` por instituicao;
- conecta os containers na rede externa `moodle_net`.

Para `escola-i`, o script garante que exista um servico parecido com:

```yaml
services:
  moodle_escola_i:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_i
    restart: unless-stopped
    env_file:
      - ./secrets/escola-i.local.env
    volumes:
      - moodledata_escola_i:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m
```

Campos relevantes:

- `image`: imagem Moodle padronizada usada por todas as instituicoes.
- `container_name`: nome fixo do container, usado pelo Caddy e cron.
- `env_file`: arquivo de variaveis sensiveis e configuracoes do tenant.
- `volumes`: monta o volume persistente da instituicao em `/var/www/moodledata`.
- `networks`: liga o container a `moodle_net`, rede onde tambem estao DB, Redis e proxy.
- `cpus`: limite de CPU.
- `mem_limit`: limite maximo de memoria.
- `mem_reservation`: memoria reservada.

O script tambem garante o volume:

```yaml
volumes:
  moodledata_escola_i:
    name: moodledata_escola_i
```

Esse volume persiste arquivos do Moodle, incluindo uploads, cache local,
sessoes quando aplicavel e o arquivo do token REST gerado em
`/var/www/moodledata/w3soft/ws-token.txt`.

Detalhe de implementacao:

- o script insere o bloco do servico antes da chave `volumes:`;
- insere o bloco do volume antes da chave `networks:`;
- verifica a existencia procurando strings como `  moodle_escola_i:` e
  `  moodledata_escola_i:`.

Isso e simples e funciona no formato atual do arquivo, mas depende da estrutura
textual do YAML. Se o arquivo for reorganizado de forma muito diferente, essa
estrategia pode falhar.

### `proxy/Caddyfile.local`

Tipo: arquivo modificado.

Funcao:

- configura o Caddy, proxy reverso compartilhado;
- roteia cada caminho `/i/{slug}/*` para o container Moodle correto;
- protege rotas desconhecidas retornando `401`.

Para `escola-i`, o script garante tres coisas.

1. Matcher de rota:

```caddy
@tenantescolai path /i/escola-i/*
```

2. Redirect da URL sem barra final para a URL com barra final:

```caddy
redir /i/escola-i /i/escola-i/
```

3. Proxy para o container Moodle:

```caddy
handle @tenantescolai {
    reverse_proxy moodle_escola_i:80
}
```

Por que a barra final importa:

- `http://localhost:8088/i/escola-i` redireciona para
  `http://localhost:8088/i/escola-i/`;
- isso evita problemas com links relativos, assets e redirecionamentos do Moodle.

Por que o `reverse_proxy moodle_escola_i:80` funciona:

- o Caddy e o Moodle estao na mesma rede Docker `moodle_net`;
- dentro de uma rede Docker Compose, o nome do container/servico pode ser usado
  como DNS interno;
- o Moodle escuta HTTP na porta 80 dentro do container.

Detalhe de implementacao:

- o script procura o bloco fallback `handle { ... 401 ... }`;
- insere o novo `handle @tenant...` antes desse fallback;
- se o fallback nao existir com o texto esperado, o script falha com
  `Caddy fallback 401 block not found.`

### `config/moodle-cron-tenants.txt`

Tipo: arquivo modificado.

Funcao:

- lista os containers Moodle que devem receber execucao de cron;
- e a fonte de verdade para os scripts de cron centralizado.

Para `escola-i`, o script adiciona:

```text
moodle_escola_i
```

O arquivo aceita comentarios e linhas vazias, que sao ignorados pelos scripts
`scripts/run-moodle-crons.sh` e `scripts/run-moodle-crons-distributed.sh`.

### `secrets/escola-i.local.env`

Tipo: arquivo criado ou atualizado.

Funcao:

- guarda variaveis de ambiente da instituicao;
- guarda credenciais sensiveis;
- alimenta o container Moodle via `env_file` do Docker Compose.

O script cria o arquivo com permissao `0600` quando nao esta em `--dry-run`.
Permissao `0600` significa: somente o dono do arquivo pode ler e escrever.

O arquivo e ignorado pelo Git via `.gitignore`:

```text
secrets/*.env
```

Grupos de variaveis geradas:

```text
MOODLE_URL
MOODLE_DB_HOST
MOODLE_DB_NAME
MOODLE_DB_USER
MOODLE_DB_PASSWORD
MOODLE_DATAROOT
MOODLE_PUBLIC_SLUG
MOODLE_TENANT_ID
MOODLE_REDIS_HOST
MOODLE_REDIS_PORT
MOODLE_REDIS_PREFIX

MOODLE_AUTO_BOOTSTRAP
MOODLE_SITE_FULLNAME
MOODLE_SITE_SHORTNAME
MOODLE_SITE_SUMMARY
MOODLE_SUPPORT_EMAIL

MOODLE_ADMIN_USER
MOODLE_ADMIN_PASSWORD
MOODLE_ADMIN_FIRSTNAME
MOODLE_ADMIN_LASTNAME
MOODLE_ADMIN_EMAIL
MOODLE_ADMIN_CITY
MOODLE_ADMIN_COUNTRY
MOODLE_ADMIN_TIMEZONE
MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL

MOODLE_WS_SERVICE_NAME
MOODLE_WS_SERVICE_SHORTNAME
MOODLE_WS_FUNCTIONS
MOODLE_WS_USER_USERNAME
MOODLE_WS_USER_PASSWORD
MOODLE_WS_USER_FIRSTNAME
MOODLE_WS_USER_LASTNAME
MOODLE_WS_USER_EMAIL
MOODLE_WS_USER_CITY
MOODLE_WS_USER_COUNTRY
MOODLE_WS_USER_TIMEZONE
MOODLE_WS_ROLE_SHORTNAME
MOODLE_WS_TOKEN_FILE
MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME
```

Valores derivados de `escola-i`:

```text
MOODLE_URL=http://localhost:8088/i/escola-i
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_i
MOODLE_DB_USER=moodle_escola_i
MOODLE_DB_PASSWORD=<databasePassword do JSON>
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola-i
MOODLE_TENANT_ID=escola-i-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_i_
```

Senhas automaticas:

- `MOODLE_ADMIN_PASSWORD` e gerada automaticamente;
- `MOODLE_WS_USER_PASSWORD` e gerada automaticamente;
- as senhas geradas possuem 28 caracteres alfanumericos mais `!7`;
- o sufixo `!7` ajuda a cumprir politicas comuns do Moodle: letra, numero e
  caractere nao alfanumerico.

Comportamento em reexecucao:

- o script monta defaults novos;
- le o arquivo existente, se houver;
- faz merge usando os valores existentes por cima dos defaults;
- portanto senhas ja geradas e ajustes manuais no `.env` sao preservados.

Essa parte e importante: reexecutar o script nao troca automaticamente a senha
do admin nem do usuario tecnico se o secret ja existe.

### `docker-compose.infra.yml`

Tipo: arquivo lido indiretamente pelo Docker, nao alterado pelo script.

Funcao:

- declara os servicos compartilhados: MariaDB, Redis e Caddy;
- cria a rede `moodle_net`;
- monta o `proxy/Caddyfile.local` dentro do container Caddy.

Servicos:

```text
db      -> container moodle_db, imagem mariadb:10.11
redis   -> container moodle_redis, imagem redis:7-alpine
proxy   -> container moodle_proxy, imagem caddy:2-alpine
```

O script usa esse arquivo quando executa:

```sh
docker compose -f docker-compose.infra.yml restart proxy
```

Isso faz o Caddy reler o `Caddyfile.local` atualizado.

### `moodle/Dockerfile`

Tipo: arquivo lido pelo Docker durante build, nao alterado pelo script.

Funcao:

- define a imagem Moodle local usada por todas as instituicoes;
- parte de `php:8.3-apache`;
- instala dependencias do sistema;
- instala extensoes PHP necessarias ao Moodle;
- clona o Moodle `MOODLE_500_STABLE`;
- baixa o pacote de idioma `pt_br`;
- copia arquivos customizados do projeto.

Arquivos copiados para a imagem:

```text
moodle/php.ini                         -> /usr/local/etc/php/conf.d/moodle.ini
moodle/config.php                      -> /var/www/html/config.php
moodle/bootstrap/provision.php         -> /var/www/html/bootstrap/provision.php
moodle/docker-entrypoint.sh            -> /usr/local/bin/moodle-entrypoint
```

O script usa esse Dockerfile quando executa:

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
```

### `moodle/config.php`

Tipo: arquivo copiado para a imagem, nao alterado pelo script.

Funcao:

- e o `config.php` real do Moodle dentro da imagem;
- le configuracoes por variaveis de ambiente;
- configura conexao com MariaDB;
- configura `wwwroot`;
- configura `dataroot`;
- configura cookie de sessao por slug;
- configura sessoes Redis quando `MOODLE_REDIS_HOST` existe.

Pontos importantes:

```php
$CFG->dbname = moodle_env_required('MOODLE_DB_NAME');
$CFG->dbuser = moodle_env_required('MOODLE_DB_USER');
$CFG->dbpass = moodle_env_required('MOODLE_DB_PASSWORD');
$CFG->wwwroot = moodle_env_required('MOODLE_URL');
```

Esse desenho permite que a mesma imagem seja usada por varias instituicoes. O
que muda entre elas nao e o codigo da imagem, e sim o arquivo `.env`.

Sessoes por instituicao:

```php
$CFG->sessioncookie = 'MoodleSession_' . $sessionSlug;
```

Isso evita conflito de cookies entre instituicoes acessadas no mesmo dominio.

Redis:

```php
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_prefix = $redisPrefix . 'session_';
```

O prefixo `escola_i_session_` separa sessoes da instituicao das sessoes de
outros tenants dentro do mesmo Redis.

### `moodle/docker-entrypoint.sh`

Tipo: arquivo copiado para a imagem, executado quando o container inicia.

Funcao:

- preparar Apache para servir o Moodle no caminho publico correto;
- validar variaveis obrigatorias;
- aguardar o banco ficar disponivel;
- instalar o Moodle em banco vazio;
- recusar bancos parcialmente instalados;
- rodar upgrade CLI;
- chamar o provisionamento PHP customizado;
- iniciar o Apache.

Fluxo simplificado:

```text
1. configure_public_path
2. bootstrap_moodle apache2-foreground
3. set_bootstrap_defaults
4. validate_bootstrap_environment
5. criar/chown do MOODLE_DATAROOT
6. wait_for_database
7. verificar se mdl_config existe
8. se banco vazio: install_database.php
9. exportar MOODLE_BOOTSTRAP_FIRST_INSTALL
10. rodar admin/cli/upgrade.php --non-interactive
11. rodar bootstrap/provision.php
12. exec docker-php-entrypoint apache2-foreground
```

`configure_public_path`:

- extrai o path de `MOODLE_URL`, por exemplo `/i/escola-i`;
- cria `/etc/apache2/conf-enabled/moodle-public-path.conf`;
- adiciona aliases Apache:

```apache
Alias /i/escola-i/ /var/www/html/
Alias /i/escola-i /var/www/html
```

Isso permite que o Moodle responda corretamente quando acessado por subcaminho,
nao pela raiz do dominio.

`wait_for_database`:

- tenta executar `SELECT 1`;
- usa `mariadb --ssl=0`;
- repete ate o banco responder ou ate esgotar tentativas.

Instalacao do Moodle:

- o script considera instalado quando a tabela `mdl_config` existe;
- se nao existe nenhuma tabela `mdl_%`, roda:

```sh
php /var/www/html/admin/cli/install_database.php \
  --lang=pt_br \
  --adminuser=<admin> \
  --adminpass=<senha> \
  --adminemail=<email> \
  --fullname=<nome do site> \
  --shortname=<slug> \
  --summary=<resumo> \
  --supportemail=<email suporte> \
  --agree-license
```

Estado inconsistente:

- se existem tabelas `mdl_%`, mas nao existe `mdl_config`, o entrypoint para;
- isso evita continuar sobre um banco parcialmente instalado.

### `moodle/bootstrap/provision.php`

Tipo: arquivo copiado para a imagem, executado pelo entrypoint.

Funcao:

- aplicar configuracoes pos-instalacao dentro do Moodle;
- criar/atualizar usuario tecnico de integracao;
- habilitar Web Services REST;
- criar servico externo;
- configurar papel/capacidades;
- gerar ou reutilizar token REST;
- gravar token no volume da instituicao.

Fluxo principal:

```text
1. update_site_identity
2. update_admin_user
3. ensure_webservice_settings
4. ensure_service
5. ensure_ws_user
6. ensure_ws_role
7. authorize_service_user
8. ensure_token
9. write_token_file
```

Alteracoes internas no Moodle:

- atualiza o curso especial `SITEID`, que representa a identidade do site;
- define `supportemail`;
- define `timezone`;
- atualiza nome, email, cidade, pais e timezone do admin;
- pode forcar troca de senha do admin na primeira instalacao;
- habilita `enablewebservices`;
- garante que `rest` esteja em `webserviceprotocols`;
- cria/atualiza o servico externo `w3soft_student_sync`;
- adiciona funcoes REST ao servico;
- cria/atualiza usuario `svc_integracao`;
- cria/atualiza papel `w3soft_ws_integration`;
- atribui capacidades ao papel;
- atribui o papel ao usuario tecnico no contexto global;
- permite que esse papel atribua o papel `student`;
- autoriza o usuario tecnico no servico externo;
- cria ou reutiliza token permanente;
- grava o token em `/var/www/moodledata/w3soft/ws-token.txt`.

Funcoes REST padrao:

```text
core_webservice_get_site_info
core_course_get_courses
core_course_get_courses_by_field
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

Capacidades padrao:

```text
webservice/rest:use
moodle/webservice:createtoken
moodle/course:view
moodle/course:viewhiddencourses
moodle/user:create
moodle/user:viewdetails
moodle/user:viewhiddendetails
moodle/course:useremail
moodle/user:update
enrol/manual:enrol
```

Arquivos gerados dentro do volume:

```text
/var/www/moodledata/w3soft/ws-token.txt
```

Permissoes:

- diretorio do token: `0700`;
- arquivo do token: `0600`.

O token nao e impresso em logs.

### `moodle/php.ini`

Tipo: arquivo copiado para a imagem, nao alterado pelo script.

Funcao:

- ajusta limites PHP usados pelo Moodle.

Valores atuais:

```ini
memory_limit = 512M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 300
max_input_vars = 5000

opcache.enable = 1
opcache.memory_consumption = 128
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
```

OPcache e um cache de bytecode PHP. Ele reduz custo de interpretar arquivos PHP
repetidamente em cada requisicao.

### `scripts/run-moodle-crons.sh`

Tipo: arquivo nao alterado pelo provisionamento, mas usa a entrada criada em
`config/moodle-cron-tenants.txt`.

Funcao:

- executa o cron Moodle dentro de cada container listado;
- cria logs por instituicao em `logs/moodle-cron/{tenant}.log`;
- usa lock por instituicao em `/tmp` ou `$TMPDIR` para evitar concorrencia.

Comando executado para cada tenant:

```sh
docker exec -u www-data "$tenant" php /var/www/html/admin/cli/cron.php
```

O usuario `www-data` e importante porque e o usuario do Apache/PHP dentro do
container. Isso evita criar arquivos do Moodle como `root`.

### `scripts/run-moodle-crons-distributed.sh`

Tipo: arquivo nao alterado pelo provisionamento.

Funcao:

- le `config/moodle-cron-tenants.txt`;
- distribui as instituicoes em ate 4 janelas por minuto: 0s, 15s, 30s e 45s;
- chama `scripts/run-moodle-crons.sh` para cada grupo.

Objetivo:

- evitar que todos os containers rodem cron ao mesmo tempo;
- reduzir pico de CPU, memoria e I/O.

## Banco de dados

Quando `--create-db` ou `--apply-all` e usado, o script executa SQL dentro do
container `moodle_db`.

Comando:

```sh
docker exec -i moodle_db sh -c 'mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD"'
```

SQL gerado para `escola-i`:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_i
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_i'@'%'
  IDENTIFIED BY 'senha-local-escola-i';

ALTER USER 'moodle_escola_i'@'%'
  IDENTIFIED BY 'senha-local-escola-i';

GRANT ALL PRIVILEGES ON moodle_escola_i.*
  TO 'moodle_escola_i'@'%';

FLUSH PRIVILEGES;
```

Por que `CREATE DATABASE IF NOT EXISTS`:

- permite reexecutar sem erro caso o banco ja exista.

Por que `CREATE USER IF NOT EXISTS` seguido de `ALTER USER`:

- cria o usuario se faltar;
- atualiza a senha se o usuario ja existir.

Por que `GRANT ALL PRIVILEGES ON moodle_escola_i.*`:

- da ao usuario da instituicao controle somente sobre seu proprio banco.

Por que `utf8mb4_unicode_ci`:

- `utf8mb4` suporta Unicode completo;
- `unicode_ci` faz comparacoes case-insensitive adequadas para textos.

Depois que o container Moodle sobe, o proprio Moodle cria muitas tabelas com
prefixo `mdl_` dentro do banco da instituicao. O entrypoint usa a existencia de
`mdl_config` como indicador de instalacao concluida.

Tabelas/configuracoes relevantes afetadas depois da instalacao:

```text
mdl_config
mdl_course
mdl_user
mdl_external_services
mdl_external_services_functions
mdl_external_services_users
mdl_external_tokens
mdl_role
mdl_role_capabilities
mdl_role_assignments
mdl_role_allow_assign
```

Os nomes fisicos podem variar conforme versao do Moodle e prefixo, mas neste
projeto o prefixo configurado e `mdl_`.

## Docker e Compose

### Infraestrutura compartilhada

Subida esperada da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml up -d
```

Esse Compose cria:

```text
moodle_db
moodle_redis
moodle_proxy
moodle_net
moodle_db_data
moodle_redis_data
moodle_caddy_data
moodle_caddy_config
```

### Instituicoes

Subida de uma instituicao especifica:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_i
```

Esse comando:

- cria o volume `moodledata_escola_i` se ainda nao existir;
- cria ou atualiza o container `moodle_escola_i`;
- injeta variaveis de `secrets/escola-i.local.env`;
- conecta o container na rede `moodle_net`;
- inicia o entrypoint `moodle-entrypoint`.

### Build da imagem

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
```

Esse comando precisa ser executado quando arquivos da imagem mudam, por exemplo:

- `moodle/Dockerfile`;
- `moodle/config.php`;
- `moodle/docker-entrypoint.sh`;
- `moodle/bootstrap/provision.php`;
- `moodle/php.ini`.

Se apenas arquivos de Compose, Caddy ou secret mudaram, rebuild da imagem pode
nao ser necessario.

### Reinicio do proxy

```sh
docker compose -f docker-compose.infra.yml restart proxy
```

Necessario porque `proxy/Caddyfile.local` e montado como arquivo no container
Caddy. Ao reiniciar, o Caddy passa a usar as novas rotas.

## Fluxo completo do `--apply-all`

```text
Usuario executa:
scripts/provision-institution.py tmp/escola-i.json --apply-all

1. Python valida tmp/escola-i.json
   - checa campos obrigatorios
   - valida slug

2. Python atualiza arquivos host
   - docker-compose.instituicoes.yml
   - proxy/Caddyfile.local
   - config/moodle-cron-tenants.txt
   - secrets/escola-i.local.env

3. Python cria/atualiza banco
   - entra em moodle_db via docker exec
   - cria banco moodle_escola_i
   - cria/atualiza usuario moodle_escola_i
   - aplica grants

4. Python builda imagem Moodle
   - docker build -t w3soft/moodle:2026.07.1-local ./moodle

5. Python sobe container
   - docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_i

6. Container inicia entrypoint
   - configura Apache para /i/escola-i
   - valida variaveis
   - espera MariaDB
   - instala Moodle se banco estiver vazio
   - roda upgrade do Moodle
   - chama bootstrap/provision.php

7. PHP provisiona Moodle internamente
   - identidade do site
   - admin
   - Web Services REST
   - usuario tecnico
   - papel e permissoes
   - token REST

8. Python reinicia proxy
   - docker compose -f docker-compose.infra.yml restart proxy

9. Resultado
   - http://localhost:8088/i/escola-i/ deve responder pelo Moodle da instituicao
```

## Resultado final esperado

Ao final do provisionamento completo, devem existir:

No host:

```text
docker-compose.instituicoes.yml com moodle_escola_i
docker-compose.instituicoes.yml com volume moodledata_escola_i
proxy/Caddyfile.local com rota /i/escola-i/*
config/moodle-cron-tenants.txt com moodle_escola_i
secrets/escola-i.local.env
```

No Docker:

```text
container moodle_escola_i
volume moodledata_escola_i
imagem w3soft/moodle:2026.07.1-local
rota Caddy ativa no container moodle_proxy
```

No MariaDB:

```text
banco moodle_escola_i
usuario moodle_escola_i
permissoes do usuario sobre moodle_escola_i.*
tabelas Moodle mdl_* depois da primeira inicializacao
```

Dentro do Moodle:

```text
site com nome Escola I
admin configurado
Web Services habilitados
protocolo REST habilitado
servico externo w3soft_student_sync
usuario tecnico svc_integracao
papel w3soft_ws_integration
token REST persistido no volume
```

## Como validar

Validar sintaxe do Compose de instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml config
```

Validar se o servico aparece:

```sh
docker compose -f docker-compose.instituicoes.yml config --services
```

Validar containers:

```sh
docker compose -f docker-compose.infra.yml ps
docker compose -f docker-compose.instituicoes.yml ps
```

Validar logs do container Moodle:

```sh
docker logs moodle_escola_i
```

Mensagens esperadas em algum momento:

```text
[moodle-entrypoint] Database is available.
[moodle-entrypoint] Running Moodle CLI upgrade check.
[moodle-entrypoint] Running tenant provisioning.
[moodle-bootstrap] Tenant provisioning finished.
```

Validar URL:

```sh
curl -I http://localhost:8088/i/escola-i/
```

Validar token sem imprimir o valor:

```sh
docker exec moodle_escola_i sh -c 'test -s /var/www/moodledata/w3soft/ws-token.txt && ls -l /var/www/moodledata/w3soft/ws-token.txt'
```

Validar banco dentro do MariaDB:

```sh
docker exec -i moodle_db sh -c 'mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '\''moodle_escola_i'\'';"'
```

Validar cron manualmente:

```sh
scripts/run-moodle-crons.sh moodle_escola_i
```

## Erros comuns e diagnostico

### JSON invalido

Sintoma:

```text
ERROR: Invalid JSON in ...
```

Diagnostico:

- verificar virgulas;
- verificar aspas;
- validar com `python -m json.tool tmp/escola-i.json`.

### Campo obrigatorio ausente

Sintoma:

```text
ERROR: Missing required field in JSON: publicUrl
```

Diagnostico:

- comparar o JSON com a lista de campos obrigatorios;
- evitar valores vazios ou `null`.

### Slug invalido

Sintoma:

```text
ERROR: slug must use lowercase letters, numbers and hyphens, and cannot start or end with hyphen
```

Exemplos invalidos:

```text
Escola-I
escola_i
-escola-i
escola-i-
```

Exemplo valido:

```text
escola-i
```

### Infraestrutura nao esta no ar

Sintoma:

```text
docker exec ... moodle_db ... No such container
```

Diagnostico:

```sh
docker compose -f docker-compose.infra.yml ps
```

Correcao:

```sh
docker compose -f docker-compose.infra.yml up -d
```

### Banco nao fica disponivel para o Moodle

Sintoma nos logs:

```text
[moodle-entrypoint] ERROR: Database did not become available after ...
```

Possiveis causas:

- banco `moodle_escola_i` nao foi criado;
- usuario `moodle_escola_i` nao existe;
- senha do `.env` diverge da senha no MariaDB;
- `MOODLE_DB_HOST` errado;
- container nao esta na rede `moodle_net`.

Comandos uteis:

```sh
docker logs moodle_escola_i
docker exec moodle_escola_i env | sort
docker exec moodle_db mariadb --ssl=0 -uroot -p
```

### Banco parcialmente instalado

Sintoma:

```text
Database has Moodle tables but mdl_config is missing.
```

Significado:

- existem tabelas com prefixo `mdl_`;
- a tabela principal `mdl_config` nao existe;
- a instalacao anterior provavelmente falhou no meio.

Acao:

- nao continuar automaticamente;
- inspecionar o banco;
- decidir se sera recuperado ou recriado.

### Caddy nao roteia para a instituicao

Sintomas:

- `401`;
- `404`;
- erro de gateway;
- rota `/i/escola-i/` nao abre.

Diagnostico:

```sh
sed -n '1,160p' proxy/Caddyfile.local
docker logs moodle_proxy
docker compose -f docker-compose.infra.yml restart proxy
docker inspect moodle_escola_i
```

Verificar se existem:

```caddy
@tenantescolai path /i/escola-i/*
redir /i/escola-i /i/escola-i/
handle @tenantescolai {
    reverse_proxy moodle_escola_i:80
}
```

### Imagem desatualizada

Sintoma:

- alteracoes em `moodle/docker-entrypoint.sh` ou `moodle/bootstrap/provision.php`
  nao aparecem no container;
- logs antigos continuam aparecendo.

Causa:

- o container usa uma imagem ja buildada anteriormente.

Correcao:

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_i
```

### Secret existente preservando valor antigo

Sintoma:

- mudar `databasePassword` no JSON nao muda o `.env`;
- senha antiga continua sendo usada.

Causa:

- `upsert_env_file` preserva valores existentes no arquivo secret.

Acao:

- editar conscientemente `secrets/escola-i.local.env`;
- ou remover o arquivo e provisionar novamente;
- depois alinhar senha no MariaDB com `--create-db` ou `--apply-all`.

### Cron nao executa para a instituicao

Sintomas:

- nao ha log para o tenant em `logs/moodle-cron`;
- tarefas agendadas do Moodle nao rodam.

Diagnostico:

```sh
grep moodle_escola_i config/moodle-cron-tenants.txt
scripts/run-moodle-crons.sh moodle_escola_i
```

Possiveis causas:

- container nao esta listado;
- container nao existe;
- container existe, mas esta parado;
- outro cron ainda esta segurando lock.

## Pontos de atencao para evolucao

O script atual e adequado para ambiente local/laboratorio, mas ha pontos a
considerar antes de transformar isso em fluxo de producao.

### Edicao textual de YAML e Caddyfile

O script usa `str.replace` em arquivos de texto. Isso e pragmatico, mas sensivel
a mudancas de formatacao.

Para producao, considerar:

- parser YAML para Compose;
- template ou gerador estruturado para Caddy;
- validacao automatica apos escrever arquivos.

### Concorrencia

Se duas instituicoes forem provisionadas ao mesmo tempo, os dois processos podem
tentar editar os mesmos arquivos.

Para producao, considerar:

- fila de jobs;
- lock global de provisionamento;
- worker unico para escrita de arquivos;
- estado persistido por etapa.

### Secrets

Hoje os secrets ficam em arquivos `.env` locais.

Para producao, considerar:

- secret manager;
- criptografia em repouso;
- rotacao de credenciais;
- auditoria de acesso;
- evitar permissao ampla ao usuario que roda Docker.

### Healthcheck antes de marcar sucesso

O script considera o comando Docker bem-sucedido como fim do fluxo, mas o Moodle
pode ainda estar instalando internamente.

Para producao, considerar:

- healthcheck HTTP em `/i/{slug}/`;
- verificacao do token;
- verificacao de status no banco;
- estado `Provisioning`, `Active` e `Failed`.

## Resumo operacional

Para criar uma instituicao local do inicio ao fim:

```sh
docker compose -f docker-compose.infra.yml up -d
scripts/provision-institution.py tmp/escola-i.json --apply-all
docker logs moodle_escola_i
curl -I http://localhost:8088/i/escola-i/
```

O script Python prepara o ambiente externo da instituicao. O container Moodle,
ao iniciar, conclui a instalacao e executa o provisionamento interno. Por isso o
fluxo real e dividido em duas fases:

```text
Fase 1, host:
  JSON -> Compose -> Caddy -> cron -> secrets -> banco -> imagem -> container

Fase 2, container:
  entrypoint -> instalacao Moodle -> upgrade -> provisionamento PHP -> token REST
```
