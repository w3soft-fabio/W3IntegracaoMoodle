# Criar manualmente uma instancia Moodle por instituicao

Este guia cria uma nova instituicao sem usar `scripts/provision-institution.py`.
Use-o quando for necessario conferir ou executar cada etapa manualmente.

Exemplo adotado neste documento:

```text
Nome exibido:        Escola Nova
Slug publico:        escola-nova
Identificador:       escola_nova
Container:           moodle_escola_nova
Banco/usuario:       moodle_escola_nova
Volume:              moodledata_escola_nova
URL local:           http://localhost:8088/i/escola-nova/
```

O slug publico usa letras minusculas, numeros e hifens. Para nomes de banco,
container, volume e prefixo Redis, troque os hifens por `_`.

## Pre-requisitos

Execute os comandos a partir da raiz do repositorio:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

O Docker Desktop precisa estar em execucao. A infraestrutura compartilhada deve
estar disponivel antes de criar a instituicao:

```sh
docker compose -f docker-compose.infra.yml up -d
docker compose -f docker-compose.infra.yml ps
```

Confirme que `moodle_db`, `moodle_redis` e `moodle_proxy` estao ativos; o banco
e o Redis devem ficar `healthy`.

## Arquivos que devem ser criados ou modificados

Para cada instituicao, modifique estes quatro arquivos:

| Arquivo | Alteracao |
| --- | --- |
| `secrets/escola-nova.local.env` | Criar as variaveis e credenciais exclusivas da instituicao. |
| `docker-compose.instituicoes.yml` | Adicionar o servico Moodle e seu volume persistente. |
| `proxy/Caddyfile.local` | Adicionar a rota publica e o proxy para o container. |
| `config/moodle-cron-tenants.txt` | Adicionar o nome do container ao cron centralizado. |

Nao modifique `docker-compose.infra.yml` para incluir uma escola: ele contem
apenas os servicos compartilhados. Tambem nao altere `moodle/config.php` ou a
imagem para uma instituicao individual; a configuracao vem do arquivo `.env`.

Os arquivos em `secrets/*.env` sao ignorados pelo Git. Nao versionar senhas ou
tokens.

## 1. Criar o arquivo de ambiente da instituicao

Crie `secrets/escola-nova.local.env` com este conteudo. Substitua todos os
valores entre `<...>` por dados reais e use senhas fortes, unicas, sem espacos
ou quebras de linha.

```dotenv
MOODLE_URL=http://localhost:8088/i/escola-nova
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_nova
MOODLE_DB_USER=moodle_escola_nova
MOODLE_DB_PASSWORD=<senha-do-banco>
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola-nova
MOODLE_TENANT_ID=escola-nova-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_nova_

MOODLE_AUTO_BOOTSTRAP=1
MOODLE_SITE_FULLNAME=Escola Nova
MOODLE_SITE_SHORTNAME=escola-nova
MOODLE_SITE_SUMMARY=
MOODLE_SUPPORT_EMAIL=suporte@escola-nova.local

MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=<senha-inicial-do-admin>
MOODLE_ADMIN_FIRSTNAME=Administrador
MOODLE_ADMIN_LASTNAME=Principal
MOODLE_ADMIN_EMAIL=admin@escola-nova.local
MOODLE_ADMIN_CITY=Maceio
MOODLE_ADMIN_COUNTRY=BR
MOODLE_ADMIN_TIMEZONE=America/Maceio
MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL=1

MOODLE_WS_SERVICE_NAME=W3Soft Student Sync
MOODLE_WS_SERVICE_SHORTNAME=w3soft_student_sync
MOODLE_WS_FUNCTIONS=core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_course_get_categories,core_course_create_categories,core_course_update_categories,core_course_create_courses,core_course_update_courses,core_user_get_users,core_user_create_users,core_user_update_users,core_cohort_create_cohorts,core_cohort_add_cohort_members,core_cohort_delete_cohort_members,enrol_manual_enrol_users,enrol_manual_unenrol_users,core_grades_update_grades,core_calendar_create_calendar_events,local_w3sync_publicar_conteudos
MOODLE_WS_EXTRA_CAPABILITIES=moodle/course:create,moodle/course:update,moodle/category:manage,moodle/cohort:manage,moodle/role:assign,moodle/grade:edit,moodle/course:manageactivities,mod/assign:grade,moodle/calendar:manageentries
MOODLE_WS_USER_USERNAME=svc_integracao
MOODLE_WS_USER_PASSWORD=<senha-do-usuario-de-integracao>
MOODLE_WS_USER_FIRSTNAME=Servico
MOODLE_WS_USER_LASTNAME=Integracao
MOODLE_WS_USER_EMAIL=svc_integracao@escola-nova.local
MOODLE_WS_USER_CITY=Maceio
MOODLE_WS_USER_COUNTRY=BR
MOODLE_WS_USER_TIMEZONE=America/Maceio
MOODLE_WS_ROLE_SHORTNAME=w3soft_ws_integration
MOODLE_WS_TOKEN_FILE=/var/www/moodledata/w3soft/ws-token.txt
MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAMES=*
```

Proteja o arquivo no host:

```sh
chmod 600 secrets/escola-nova.local.env
```

`MOODLE_URL` nao leva barra final; a URL de acesso leva. `MOODLE_PUBLIC_SLUG`
deve ser o slug publico (`escola-nova`), nao o identificador com underscore.

## 2. Declarar o container e o volume

Em `docker-compose.instituicoes.yml`, adicione o servico dentro de `services:`
e o volume dentro de `volumes:`. Mantendo o exemplo existente, o resultado e:

```yaml
services:
  moodle_escola_nova:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_nova
    restart: unless-stopped
    env_file:
      - ./secrets/escola-nova.local.env
    volumes:
      - moodledata_escola_nova:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_nova:
    name: moodledata_escola_nova

networks:
  moodle_net:
    external: true
```

Se ja houver outras instituicoes no arquivo, acrescente somente os blocos do
servico e do volume; mantenha uma unica chave `services:`, `volumes:` e
`networks:`.

Valide a sintaxe e confirme que o servico aparece:

```sh
docker compose -f docker-compose.instituicoes.yml config --quiet
docker compose -f docker-compose.instituicoes.yml config --services
```

## 3. Configurar a rota no Caddy

Em `proxy/Caddyfile.local`, adicione as tres entradas abaixo, preservando a
ordem: matcher no inicio, redirect junto aos demais redirects e `handle` antes
do `handle` final de fallback/401.

```caddy
@tenantescolanova path /i/escola-nova/*

redir /i/escola-nova /i/escola-nova/

handle @tenantescolanova {
	reverse_proxy moodle_escola_nova:80 {
		header_up Host {upstream_hostport}
	}
}
```

O nome `@tenantescolanova` deve ser unico. A rota com `/*` encaminha as paginas
e assets do Moodle, enquanto o redirect normaliza a URL sem barra final.

Valide a configuracao antes de reiniciar o proxy:

```sh
docker exec moodle_proxy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

## 4. Registrar o cron centralizado

Acrescente uma linha em `config/moodle-cron-tenants.txt`:

```text
moodle_escola_nova
```

Use exatamente o valor de `container_name`. Isso nao cria o cron por si so,
mas inclui a instituicao nas proximas execucoes de
`scripts/run-moodle-crons.sh` ou `scripts/run-moodle-crons-distributed.sh`.

## 5. Criar o banco e o usuario MariaDB

O `docker compose up` do Moodle nao cria banco nem usuario para um novo tenant.
Conecte-se como root no MariaDB; a senha sera solicitada no terminal e vem de
`secrets/infra.local.env` (`MARIADB_ROOT_PASSWORD`):

```sh
docker exec -it moodle_db mariadb --ssl=0 -uroot -p
```

No prompt `MariaDB [(none)]>`, execute o SQL abaixo. Use exatamente a mesma
senha definida em `MOODLE_DB_PASSWORD` no arquivo da etapa 1.

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_nova
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_nova'@'%'
  IDENTIFIED BY '<senha-do-banco>';

ALTER USER 'moodle_escola_nova'@'%'
  IDENTIFIED BY '<senha-do-banco>';

GRANT ALL PRIVILEGES ON moodle_escola_nova.*
  TO 'moodle_escola_nova'@'%';

FLUSH PRIVILEGES;
EXIT;
```

O `ALTER USER` torna o procedimento repetivel: se o usuario ja existir, a senha
e alinhada ao arquivo `.env`. Nao use o usuario root nas configuracoes Moodle.

Valide, sem revelar a senha:

```sh
docker exec moodle_db sh -lc 'mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD" -Nse "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '\''moodle_escola_nova'\''; SELECT CONCAT(User, '\''@'\'', Host) FROM mysql.user WHERE User = '\''moodle_escola_nova'\'';"'
```

O resultado deve listar `moodle_escola_nova` e `moodle_escola_nova@%`.

## 6. Garantir a imagem Moodle

Se a imagem `w3soft/moodle:2026.07.1-local` ainda nao existir ou se arquivos
em `moodle/` tiverem sido alterados, execute:

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
```

Se ela ja existir e nao houve mudanca na imagem, este build nao e necessario.

## 7. Subir a instituicao e recarregar o proxy

Suba somente o tenant novo e depois reinicie o Caddy para ele ler a nova rota:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_nova
docker compose -f docker-compose.infra.yml restart proxy
```

O primeiro start executa automaticamente a instalacao do Moodle, o upgrade e o
provisionamento do usuario/servico de integracao. Acompanhe os logs ate o fim:

```sh
docker compose -f docker-compose.instituicoes.yml logs -f moodle_escola_nova
```

Espere a mensagem abaixo antes de reiniciar o container ou acessar a aplicacao:

```text
[moodle-entrypoint] Automatic Moodle bootstrap finished.
```

Interromper ou reiniciar durante esse bootstrap pode deixar a flag
`upgraderunning` no banco e manter o container em loop.

## 8. Validar a instancia

Em outro terminal, confira o estado do container:

```sh
docker compose -f docker-compose.instituicoes.yml ps moodle_escola_nova
```

Ele deve estar `Up`, e nao `Restarting`. Teste a rota:

```sh
curl -I http://localhost:8088/i/escola-nova/
```

Abra no navegador:

```text
http://localhost:8088/i/escola-nova/
```

Opcionalmente, confirme que o token de integracao foi criado sem exibir seu
conteudo:

```sh
docker exec moodle_escola_nova sh -lc 'test -s /var/www/moodledata/w3soft/ws-token.txt && ls -l /var/www/moodledata/w3soft/ws-token.txt'
```

E execute o cron manualmente uma vez:

```sh
./scripts/run-moodle-crons.sh moodle_escola_nova
```

## Diagnostico rapido de 502

Um 502 nessa rota normalmente significa que o Caddy encontrou a rota, mas o
container Moodle nao esta aceitando conexoes na porta 80. Consulte:

```sh
docker compose -f docker-compose.instituicoes.yml ps moodle_escola_nova
docker compose -f docker-compose.instituicoes.yml logs --tail=200 moodle_escola_nova
docker compose -f docker-compose.infra.yml logs --tail=100 proxy
```

Casos comuns:

- `Access denied for user`: banco, usuario ou senha nao correspondem ao `.env`.
- `Database has Moodle tables ... config is missing`: a instalacao foi
  interrompida; nao reutilize esse banco sem avaliar/limpar o estado.
- `O site esta sendo atualizado`: o bootstrap foi interrompido e deixou a flag
  `upgraderunning`; pare o container antes de corrigir essa flag no banco.
- `lookup moodle_escola_nova ... no such host`: o container nao esta ativo ou
  nao esta conectado a `moodle_net`.

## Checklist final

- [ ] `secrets/escola-nova.local.env` criado, com permissao `600`.
- [ ] Servico e volume adicionados em `docker-compose.instituicoes.yml`.
- [ ] Rota e redirect adicionados em `proxy/Caddyfile.local`.
- [ ] `moodle_escola_nova` adicionado em `config/moodle-cron-tenants.txt`.
- [ ] Banco, usuario e grant criados no MariaDB.
- [ ] Bootstrap concluido sem reiniciar o container.
- [ ] URL `http://localhost:8088/i/escola-nova/` acessivel.
