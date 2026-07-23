# Instalacao limpa do Moodle Docker e compartilhamento do projeto

Este guia explica como compartilhar este projeto corretamente e como subir uma
instalacao nova em outro ambiente, sem migrar bancos, arquivos enviados,
usuarios, cursos ou qualquer dado ja existente na maquina de origem.

Use este documento quando a outra pessoa deve comecar do zero.

Para migracao com dados reais, use outro roteiro: nesse caso e necessario
exportar banco MariaDB e volumes `moodledata_*`.

## 1. O que significa instalacao limpa

Instalacao limpa significa que a pessoa de destino vai receber somente o
projeto e as configuracoes necessarias para criar um novo ambiente.

Ela nao vai receber:

- bancos existentes;
- cursos ja criados;
- usuarios ja cadastrados;
- arquivos enviados no Moodle;
- caches, sessoes e arquivos temporarios;
- tokens ja gerados em ambientes anteriores;
- certificados locais do Caddy;
- backups antigos.

Ao subir o Docker no destino, os volumes serao criados novamente e o Moodle
iniciara como uma instalacao nova.

## 2. O que deve ser compartilhado

Compartilhe os arquivos de codigo, configuracao e documentacao do projeto:

```text
docker-compose.yml
docker-compose.infra.yml
docker-compose.instituicoes.yml
config/
docs/
examples/
moodle/
proxy/
scripts/
.gitignore
```

Dentro de `moodle/`, confirme que o arquivo `moodle/config.php` esta incluido.
Neste projeto ele e necessario porque o `moodle/Dockerfile` copia esse arquivo
para dentro da imagem. Ele nao deve conter senhas fixas; deve apenas ler as
variaveis de ambiente.

Se voce for compartilhar por Git, esse deve ser o conteudo principal do
repositorio.

Se voce for compartilhar por arquivo compactado, gere um pacote contendo apenas
esses itens.

## 3. O que nao deve ser compartilhado

Nao envie dados de runtime, backups ou segredos locais:

```text
backups/
backups.zip
logs/
tmp/
secrets/*.env
*.sql
*.sql.gz
*.dump
*.tar.gz
*.zip
moodledata/
data/
cache/
localcache/
sessions/
temp/
trashdir/
```

Tambem nao envie volumes Docker. Eles nao ficam normalmente dentro da pasta do
projeto, mas guardam os dados reais do ambiente.

Volumes deste projeto podem ter nomes como:

```text
moodle_db_data
moodle_redis_data
moodle_caddy_data
moodle_caddy_config
moodledata_escola_a
moodledata_escola_b
moodledata_escola_c
```

Esses volumes devem ficar somente na maquina de origem quando a intencao for
instalacao limpa.

## 4. Preparar o projeto antes de compartilhar

Antes de enviar o projeto, confira o estado da pasta:

```bash
git status --short
```

Confira se existem arquivos sensiveis ou pesados:

```bash
find . -maxdepth 2 -type f \( -name "*.env" -o -name "*.sql" -o -name "*.dump" -o -name "*.tar.gz" -o -name "*.zip" \)
```

No Windows PowerShell:

```powershell
Get-ChildItem -Recurse -File | Where-Object {
  $_.Name -like "*.env" -or
  $_.Name -like "*.sql" -or
  $_.Name -like "*.dump" -or
  $_.Name -like "*.tar.gz" -or
  $_.Name -like "*.zip"
}
```

Se aparecerem arquivos dentro de `secrets/`, backups, dumps ou pacotes antigos,
nao inclua esses arquivos no envio.

## 5. Forma recomendada de compartilhar

A forma mais segura e usar um repositorio Git privado.

Fluxo recomendado:

```bash
git add docker-compose.yml docker-compose.infra.yml docker-compose.instituicoes.yml
git add -f moodle/config.php
git add config docs examples moodle proxy scripts .gitignore
git commit -m "Prepara projeto Moodle Docker para instalacao limpa"
git push
```

O `-f` em `git add -f moodle/config.php` e necessario se esse arquivo ainda
estiver ignorado pelo `.gitignore`. Antes de versionar, abra o arquivo e confirme
que ele nao possui senha, token ou URL sensivel fixa.

Depois, a outra pessoa clona o projeto:

```bash
git clone <url-do-repositorio>
cd moodle-docker
```

Nao coloque arquivos reais de `secrets/*.env` no Git. Envie modelos
`*.example`, ou envie os valores por um canal seguro separado quando necessario.

## 6. Compartilhar por arquivo compactado

Se nao for usar Git, crie um pacote manual somente com os arquivos necessarios.

No macOS ou Linux, uma opcao e usar `tar` excluindo dados locais:

```bash
tar \
  --exclude='./.git' \
  --exclude='./backups' \
  --exclude='./backups.zip' \
  --exclude='./logs' \
  --exclude='./tmp' \
  --exclude='./secrets/*.env' \
  --exclude='./*.sql' \
  --exclude='./*.sql.gz' \
  --exclude='./*.dump' \
  --exclude='./*.tar.gz' \
  --exclude='./*.zip' \
  -czf moodle-docker-instalacao-limpa.tar.gz .
```

No Windows, crie uma nova pasta temporaria e copie somente:

```text
docker-compose.yml
docker-compose.infra.yml
docker-compose.instituicoes.yml
config
docs
examples
moodle
proxy
scripts
.gitignore
```

Depois compacte essa pasta pelo Explorer ou PowerShell.

Nao compacte a pasta inteira sem revisar, porque ela pode conter `backups/`,
`backups.zip`, logs e arquivos locais.

## 7. Pre-requisitos no ambiente de destino

A pessoa que vai instalar precisa ter:

- Docker instalado;
- Docker Compose disponivel pelo comando `docker compose`;
- acesso ao terminal;
- portas livres conforme o modo escolhido.

Portas usadas neste projeto:

```text
8080  -> Moodle simples, usando docker-compose.yml
8088  -> proxy Caddy HTTP, usando docker-compose.infra.yml
8443  -> proxy Caddy HTTPS local/reservado
```

Validar Docker:

```bash
docker --version
docker compose version
docker info
```

No Windows, use Docker Desktop com WSL 2 habilitado.

## 8. Criar arquivos de ambiente

Este projeto usa arquivos em `secrets/*.env` para passar variaveis ao Docker.
Esses arquivos nao devem vir com dados reais da maquina de origem.

No destino, crie a pasta:

```bash
mkdir -p secrets
```

No Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force secrets
```

### 8.1. Ambiente simples

Para subir somente `docker-compose.yml`, crie `secrets/local.env`:

```text
MOODLE_URL=http://localhost:8080
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=moodle
MOODLE_DB_PASSWORD=moodlepass
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=local

MOODLE_AUTO_BOOTSTRAP=1
MOODLE_SITE_FULLNAME=Moodle Local
MOODLE_SITE_SHORTNAME=local
MOODLE_SITE_SUMMARY=
MOODLE_SUPPORT_EMAIL=suporte@local.test

MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=Admin@12345
MOODLE_ADMIN_FIRSTNAME=Administrador
MOODLE_ADMIN_LASTNAME=Principal
MOODLE_ADMIN_EMAIL=admin@local.test
MOODLE_ADMIN_CITY=Maceio
MOODLE_ADMIN_COUNTRY=BR
MOODLE_ADMIN_TIMEZONE=America/Maceio
MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL=1

MOODLE_WS_SERVICE_NAME=W3Soft Student Sync
MOODLE_WS_SERVICE_SHORTNAME=w3soft_student_sync
MOODLE_WS_FUNCTIONS=core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_course_create_courses,core_course_update_courses,core_user_get_users_by_field,core_user_create_users,enrol_manual_enrol_users
MOODLE_WS_USER_USERNAME=svc_integracao
MOODLE_WS_USER_PASSWORD=Servico@12345
MOODLE_WS_USER_FIRSTNAME=Servico
MOODLE_WS_USER_LASTNAME=Integracao
MOODLE_WS_USER_EMAIL=svc_integracao@local.test
MOODLE_WS_USER_CITY=Maceio
MOODLE_WS_USER_COUNTRY=BR
MOODLE_WS_USER_TIMEZONE=America/Maceio
MOODLE_WS_ROLE_SHORTNAME=w3soft_ws_integration
MOODLE_WS_TOKEN_FILE=/var/www/moodledata/w3soft/ws-token.txt
MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAMES=*
```

Para um ambiente real, troque as senhas antes de subir.

### 8.2. Infraestrutura multi-instituicao

Para usar `docker-compose.infra.yml`, crie `secrets/infra.local.env`:

```text
MARIADB_DATABASE=moodle
MARIADB_USER=moodle
MARIADB_PASSWORD=moodlepass
MARIADB_ROOT_PASSWORD=rootpass
```

Troque `MARIADB_ROOT_PASSWORD` e as demais senhas em qualquer ambiente que nao
seja apenas teste local.

Para cada instituicao, o projeto espera um arquivo como:

```text
secrets/escola-a.local.env
secrets/escola-b.local.env
```

Esses arquivos podem ser criados manualmente ou pelo script
`scripts/provision-institution.py`.

## 9. Opcao A: subir ambiente simples do zero

Use esta opcao quando quiser apenas um Moodle local acessivel em
`http://localhost:8080`.

Na raiz do projeto:

```bash
docker compose build
docker compose up -d
```

Verifique os containers:

```bash
docker compose ps
```

Acompanhe os logs:

```bash
docker compose logs -f moodle
```

Acesse:

```text
http://localhost:8080
```

Na primeira subida, o Moodle pode demorar alguns minutos para instalar tabelas,
configurar o site e preparar o bootstrap.

## 10. Opcao B: subir ambiente multi-instituicao do zero

Use esta opcao quando quiser usar a arquitetura com:

- MariaDB compartilhado;
- Redis compartilhado;
- Caddy como proxy;
- um container Moodle por instituicao.

### 10.1. Subir a infraestrutura

```bash
docker compose -f docker-compose.infra.yml up -d
```

Verifique:

```bash
docker compose -f docker-compose.infra.yml ps
```

O proxy deve responder em:

```text
http://localhost:8088
```

### 10.2. Criar uma instituicao nova pelo script

Crie um arquivo JSON temporario com os dados da instituicao:

```json
{
  "displayName": "Escola A",
  "slug": "escola-a",
  "tenantId": "escola-a",
  "databasePassword": "TroqueEstaSenha@123",
  "publicUrl": "http://localhost:8088/i/escola-a",
  "cpu": "1.0",
  "memoryLimit": "1.5g",
  "memoryReservation": "512m"
}
```

Salve como, por exemplo:

```text
tmp/escola-a.json
```

Execute:

```bash
python3 scripts/provision-institution.py tmp/escola-a.json --apply-all
```

No Windows, se `python3` nao existir, tente:

```powershell
python scripts/provision-institution.py tmp/escola-a.json --apply-all
```

Esse comando:

- atualiza `docker-compose.instituicoes.yml`;
- atualiza `proxy/Caddyfile.local`;
- atualiza `config/moodle-cron-tenants.txt`;
- cria `secrets/escola-a.local.env`;
- cria o banco e usuario no MariaDB;
- reconstrui a imagem Moodle;
- sobe o container da instituicao;
- reinicia o proxy.

### 10.3. Subir instituicoes ja declaradas no Compose

Se os servicos ja estiverem declarados em `docker-compose.instituicoes.yml` e
os arquivos `secrets/*.local.env` ja tiverem sido criados no destino:

```bash
docker build -t w3soft/moodle:2026.07.1-local ./moodle
docker compose -f docker-compose.instituicoes.yml up -d
docker compose -f docker-compose.infra.yml restart proxy
```

Verifique:

```bash
docker compose -f docker-compose.instituicoes.yml ps
docker compose -f docker-compose.infra.yml ps
```

Acesse uma instituicao pelo proxy:

```text
http://localhost:8088/i/escola-a
```

## 11. Criar bancos manualmente, se necessario

Se nao usar `scripts/provision-institution.py --apply-all`, crie o banco da
instituicao manualmente.

Exemplo para `escola-a`:

```bash
docker exec -i moodle_db sh -c 'mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD"' <<'SQL'
CREATE DATABASE IF NOT EXISTS moodle_escola_a CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%' IDENTIFIED BY 'TroqueEstaSenha@123';
ALTER USER 'moodle_escola_a'@'%' IDENTIFIED BY 'TroqueEstaSenha@123';
GRANT ALL PRIVILEGES ON moodle_escola_a.* TO 'moodle_escola_a'@'%';
FLUSH PRIVILEGES;
SQL
```

No Windows PowerShell, uma forma simples e entrar no container:

```powershell
docker exec -it moodle_db sh
```

Dentro do container:

```sh
mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD"
```

Depois execute os comandos SQL adaptando nome do banco, usuario e senha.

## 12. Validar a instalacao

Ver containers em execucao:

```bash
docker ps
```

Ver logs da infraestrutura:

```bash
docker compose -f docker-compose.infra.yml logs -f db redis proxy
```

Ver logs de uma instituicao:

```bash
docker compose -f docker-compose.instituicoes.yml logs -f moodle_escola_a
```

Verificar se a imagem foi criada:

```bash
docker images | grep w3soft/moodle
```

No Windows PowerShell:

```powershell
docker images | Select-String w3soft/moodle
```

## 13. Como zerar o ambiente de destino

Use estes comandos somente no ambiente de destino quando a pessoa quiser apagar
a instalacao local e recomecar do zero.

Ambiente simples:

```bash
docker compose down -v
```

Ambiente multi-instituicao:

```bash
docker compose -f docker-compose.instituicoes.yml down -v
docker compose -f docker-compose.infra.yml down -v
```

O parametro `-v` apaga volumes Docker associados ao Compose. Isso remove banco,
arquivos do Moodle e dados persistidos.

## 14. Checklist antes de enviar para outra pessoa

Antes de compartilhar, confirme:

- os arquivos `secrets/*.env` reais nao foram incluidos;
- `backups/` e `backups.zip` nao foram incluidos;
- dumps `.sql`, `.dump`, `.sql.gz` nao foram incluidos;
- pacotes `.tar.gz` e `.zip` antigos nao foram incluidos;
- a outra pessoa recebeu instrucoes para criar seus proprios `secrets/*.env`;
- senhas padrao foram trocadas quando o ambiente nao for apenas teste local;
- o objetivo esta claro: instalacao limpa, sem dados anteriores.

## 15. Resumo rapido para quem vai instalar

Clone ou extraia o projeto:

```bash
cd moodle-docker
mkdir -p secrets
```

Crie `secrets/local.env` para ambiente simples ou `secrets/infra.local.env` e
os arquivos de instituicao para multi-instituicao.

Para ambiente simples:

```bash
docker compose build
docker compose up -d
```

Para multi-instituicao:

```bash
docker compose -f docker-compose.infra.yml up -d
python3 scripts/provision-institution.py tmp/escola-a.json --apply-all
```

Acesse:

```text
http://localhost:8080
```

ou:

```text
http://localhost:8088/i/escola-a
```
