# Bootstrap automatico de instituicoes Moodle

Este documento descreve a automacao implementada para criar uma nova instituicao Moodle em container, concluir a instalacao inicial sem navegador e gerar o token REST de integracao.

## Objetivo

O fluxo automatizado deve receber os dados da instituicao, preparar a infraestrutura local do tenant e deixar o Moodle acessivel diretamente na tela de login em:

```text
http://localhost:8088/i/{slug}
```

Tambem deve criar um usuario tecnico `svc_integracao`, habilitar Web Services REST, criar o servico externo `w3soft_student_sync` e persistir o token em:

```text
/var/www/moodledata/w3soft/ws-token.txt
```

O token nao e impresso em logs.

## Componentes implementados

### 1. Bootstrap no entrypoint da imagem

Arquivo:

```text
moodle/docker-entrypoint.sh
```

Responsabilidades:

- configurar o Alias Apache para servir o Moodle em `/i/{slug}`;
- validar variaveis obrigatorias de banco, site, admin e Web Service;
- aguardar o MariaDB da instituicao ficar acessivel;
- detectar se o banco Moodle ja esta instalado pela tabela `mdl_config`;
- executar `admin/cli/install_database.php --agree-license` quando o banco esta vazio;
- recusar bancos parcialmente instalados, com tabelas Moodle mas sem `mdl_config`;
- executar `admin/cli/upgrade.php --non-interactive`;
- executar o provisionamento PHP idempotente;
- iniciar o Apache somente depois do bootstrap.

Durante a criacao da Escola G foi identificado que o cliente `mariadb` da imagem podia tentar SSL por padrao. Como o MariaDB local nao oferece SSL, a checagem do banco passou a usar:

```sh
mariadb --ssl=0
```

Isso afeta somente a checagem do entrypoint. A conexao normal do Moodle continua sendo feita pelo driver PHP configurado no `config.php`.

Tambem foi ajustada a ordem dos Alias Apache:

```apache
Alias /i/escola-g/ /var/www/html/
Alias /i/escola-g /var/www/html
```

Assim o Apache deixa de emitir aviso de sobreposicao de Alias.

### 2. Provisionamento interno do Moodle

Arquivo:

```text
moodle/bootstrap/provision.php
```

Responsabilidades:

- atualizar identidade do site: nome completo, nome curto, resumo e e-mail de suporte;
- atualizar dados do admin principal;
- forcar troca de senha do admin no primeiro login quando configurado;
- habilitar `enablewebservices`;
- garantir o protocolo `rest` em `webserviceprotocols`;
- criar ou atualizar o servico externo por shortname;
- adicionar as funcoes REST exigidas;
- criar ou atualizar o usuario tecnico;
- criar ou atualizar o papel dedicado `w3soft_ws_integration`;
- atribuir capacidades ao papel tecnico;
- permitir que o papel tecnico atribua o papel alvo de matricula, por padrao `student`;
- autorizar o usuario tecnico no servico externo;
- reutilizar token ativo existente ou criar um novo token permanente;
- gravar o token em arquivo com permissao `0600`.

Capacidades padrao do papel tecnico:

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

Funcoes REST padrao:

```text
core_webservice_get_site_info
core_course_get_courses
core_course_get_courses_by_field
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

### 3. Gerador de instituicao por JSON

Arquivo:

```text
scripts/provision-institution.py
```

Esse script transforma um JSON de instituicao nos arquivos e recursos necessarios para o tenant.

Ele atualiza, de forma idempotente:

- `docker-compose.instituicoes.yml`;
- `proxy/Caddyfile.local`;
- `config/moodle-cron-tenants.txt`;
- `secrets/{slug}.local.env`.

Opcionalmente, tambem:

- cria ou atualiza o banco e usuario MariaDB;
- rebuilda a imagem `w3soft/moodle:2026.06.1-local`;
- sobe o container da instituicao;
- reinicia o proxy Caddy.

## Formato do JSON

Exemplo:

```json
{
  "displayName": "Escola G",
  "slug": "escola-g",
  "tenantId": "escola-g-local",
  "databasePassword": "senha-local-escola-g",
  "publicUrl": "http://localhost:8088/i/escola-g",
  "cpu": "1.0",
  "memoryLimit": "1.5g",
  "memoryReservation": "512m"
}
```

Campos obrigatorios:

- `displayName`;
- `slug`;
- `tenantId`;
- `databasePassword`;
- `publicUrl`;
- `cpu`;
- `memoryLimit`;
- `memoryReservation`.

O `slug` deve usar letras minusculas, numeros e hifens. Ele nao pode comecar ou terminar com hifen.

## Como criar uma instituicao

Crie um arquivo JSON, por exemplo:

```text
/tmp/escola-h.json
```

Execute o provisionamento completo:

```sh
scripts/provision-institution.py /tmp/escola-h.json --apply-all
```

Esse comando:

1. adiciona o servico `moodle_{slug_com_underscore}` ao Compose;
2. adiciona o volume `moodledata_{slug_com_underscore}`;
3. adiciona a rota `/i/{slug}` ao Caddy;
4. adiciona o container ao cron centralizado;
5. cria `secrets/{slug}.local.env`;
6. cria banco e usuario no MariaDB;
7. rebuilda a imagem Moodle local;
8. sobe o container;
9. reinicia o proxy.

Para gerar apenas os arquivos sem executar Docker:

```sh
scripts/provision-institution.py /tmp/escola-h.json
```

Para simular sem escrever nada:

```sh
scripts/provision-institution.py /tmp/escola-h.json --dry-run --apply-all
```

## Secrets gerados

O arquivo `secrets/{slug}.local.env` inclui:

- configuracao de URL, banco, Redis, slug e tenant ID;
- variaveis de bootstrap do site;
- credenciais iniciais do admin;
- credenciais do usuario tecnico;
- configuracao do servico REST e caminho do token.

As senhas de admin e do usuario tecnico sao geradas automaticamente quando o arquivo ainda nao existe. O script preserva valores existentes em reexecucoes.

Importante: as senhas geradas incluem caractere nao alfanumerico, porque a politica padrao do Moodle exige pelo menos um caractere como `!`, `*`, `-` ou `#`.

## Idempotencia

O fluxo pode ser executado mais de uma vez.

Comportamento esperado:

- se o servico ja existe no Compose, nao duplica;
- se o volume ja existe no Compose, nao duplica;
- se a rota ja existe no Caddyfile, nao duplica;
- se o container ja esta no arquivo de cron, nao duplica;
- se o secret ja existe, valores sensiveis existentes sao preservados;
- se o banco ja existe, o comando SQL mantem banco, usuario e grants atualizados;
- se o Moodle ja esta instalado, o entrypoint pula `install_database.php`;
- se o usuario tecnico, papel, servico e token ja existem, o provisionamento reutiliza.

## Validacao

Depois de subir uma instituicao, valide a rota publica:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8088/i/escola-g/
```

Resultado esperado:

```text
200
```

Valide o arquivo de token sem imprimir seu valor:

```sh
docker exec moodle_escola_g sh -c 'test -s /var/www/moodledata/w3soft/ws-token.txt && stat -c "%a %U:%G %n" /var/www/moodledata/w3soft/ws-token.txt'
```

Resultado esperado:

```text
600 www-data:www-data /var/www/moodledata/w3soft/ws-token.txt
```

Valide a API REST:

```sh
TOKEN="$(docker exec moodle_escola_g sh -c 'cat /var/www/moodledata/w3soft/ws-token.txt')"
curl -fsS -X POST http://localhost:8088/i/escola-g/webservice/rest/server.php \
  -d "wstoken=$TOKEN" \
  -d "wsfunction=core_webservice_get_site_info" \
  -d "moodlewsrestformat=json"
```

O retorno deve conter o site, o usuario do token e a versao do Moodle. Para a Escola G validada localmente:

```text
site=Escola G
user=svc_integracao
release=4.5.12+ (Build: 20260616)
```

## Observacoes operacionais

- O proxy precisa ser reiniciado ou recarregado apos adicionar nova rota.
- O Compose de instituicoes referencia uma imagem pronta, portanto a tag local precisa ser rebuildada apos alteracoes na imagem Moodle.
- O token deve ser tratado como segredo e nao deve ser versionado.
- Os arquivos `secrets/*.env` sao ignorados pelo Git.
- Para producao, substitua senhas locais por secrets gerenciados e defina e-mails reais.
