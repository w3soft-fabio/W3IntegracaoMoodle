# Bootstrap automatico de instituicoes Moodle

> Nota: o antigo orquestrador `scripts/provision-institution.py` foi removido.
> As configuracoes executadas pelo entrypoint dentro de um container continuam
> documentadas aqui, mas a criacao de uma nova instituicao deve seguir
> `docs/criar-instancia-manual-moodle.md`. O cron atual esta documentado em
> `docs/cron-moodle-systemd.md`.

Este documento descreve a automacao implementada para criar uma nova instituicao Moodle em container, concluir a instalacao inicial sem navegador e gerar o token REST de integracao.

## Objetivo

O fluxo automatizado deve receber os dados da instituicao, preparar a infraestrutura local do tenant e deixar o Moodle acessivel diretamente na tela de login em:

```text
http://localhost:8088/i/{slug}
```

Tambem deve habilitar Web Services REST, criar o servico externo restrito
`w3soft_student_sync` e persistir o token em:

```text
/var/www/moodledata/w3soft/ws-token.txt
```

O token nao e impresso em logs.

O mesmo bootstrap habilita por padrao a atividade BigBlueButton nativa do
Moodle, mas deixa a gravacao desabilitada por padrao. Ele tambem aplica a URL,
o segredo compartilhado e o algoritmo de checksum definidos no arquivo `.env`
de cada tenant.

O envio de e-mails e configurado por padrao com SMTP autenticado e TLS. As
credenciais podem ser sobrescritas no arquivo `.env` de cada tenant.

O token pertence ao administrador primario definido em `MOODLE_ADMIN_USER`. O servico externo expoe
somente a allowlist configurada em `MOODLE_WS_FUNCTIONS`.

O token deve ser tratado como segredo de alto privilegio: nao o inclua em logs,
respostas HTTP ou arquivos versionados. Para revoga-lo ou rotaciona-lo, remova o
token em **Administracao do site > Servidor > Web services > Gerenciar tokens**
e execute novamente o bootstrap. Um novo token sera criado e gravado no mesmo
arquivo com permissao `0600`. Depois, atualize o token persistido pelo
provisionador em `.provisioner/tenants/{tenantId}.json` antes de retomar as
chamadas da API; o registro nao e atualizado pelo container Moodle.

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
- habilitar por padrao o modulo de atividade `mod_bigbluebuttonbn`;
- desabilitar por padrao a gravacao de atividades BigBlueButton;
- configurar URL, segredo compartilhado e algoritmo da API BigBlueButton;
- configurar o servidor SMTP usado para enviar e-mails;
- atualizar dados do admin principal;
- forcar troca de senha do admin no primeiro login quando configurado;
- habilitar `enablewebservices`;
- garantir o protocolo `rest` em `webserviceprotocols`;
- criar ou atualizar o servico externo por shortname;
- adicionar as funcoes REST exigidas;
- autorizar o administrador principal no servico externo;
- reutilizar token ativo existente ou criar um novo token permanente;
- gravar o token em arquivo com permissao `0600`.

Funcoes REST padrao:

```text
core_webservice_get_site_info
core_course_get_courses
core_course_get_courses_by_field
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

### 3. Criacao da instituicao

O antigo gerador por JSON foi removido. Os arquivos do tenant sao preparados
conforme `docs/criar-instancia-manual-moodle.md`.

Opcionalmente, tambem:

- cria ou atualiza o banco e usuario MariaDB;
- rebuilda a imagem `w3soft/moodle:2026.07.1-local`;
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

O orquestrador antigo foi removido. Siga
`docs/criar-instancia-manual-moodle.md`. O servico da instituicao deve receber
o label `com.w3soft.moodle.role=tenant`; nao crie um container `_cron`.

## Secrets gerados

O arquivo `secrets/{slug}.local.env` inclui:

- configuracao de URL, banco, Redis, slug e tenant ID;
- variaveis de bootstrap do site;
- configuracao e credenciais do BigBlueButton;
- configuracao e credenciais do servidor SMTP;
- credenciais iniciais do admin;
- configuracao do servico REST e caminho do token.

A senha do admin e gerada automaticamente quando o arquivo ainda nao existe. O script preserva valores sensiveis existentes em reexecucoes.

Importante: as senhas geradas incluem caractere nao alfanumerico, porque a politica padrao do Moodle exige pelo menos um caractere como `!`, `*`, `-` ou `#`.

Preencha as credenciais retornadas por `bbb-conf --secret` antes de iniciar o
tenant:

```dotenv
MOODLE_BBB_ENABLED=1
MOODLE_BBB_RECORDING_DEFAULT=0
MOODLE_BBB_SERVER_URL=https://bbb.exemplo.com/bigbluebutton/
MOODLE_BBB_SHARED_SECRET=troque-pelo-segredo-do-servidor
MOODLE_BBB_CHECKSUM_ALGORITHM=SHA256
```

`MOODLE_BBB_ENABLED` assume `1` quando omitido. URL e segredo devem ser
informados juntos. Para compatibilidade com tenants existentes, quando ambos
estao vazios o modulo continua habilitado e o bootstrap registra um aviso sem
impedir a inicializacao. O segredo nunca e escrito nos logs.

`MOODLE_BBB_RECORDING_DEFAULT` assume `0` quando omitido. Assim, a atividade de
videoconferencia continua disponivel, mas a gravacao precisa ser habilitada
explicitamente por uma instituicao que necessite desse recurso.

Configuracao SMTP padrao:

```dotenv
MOODLE_SMTP_HOST=smtp.gmail.com:587
MOODLE_SMTP_AUTH_TYPE=LOGIN
MOODLE_SMTP_USER=felipew3soft@gmail.com
MOODLE_SMTP_PASSWORD=defina-a-senha-do-aplicativo
MOODLE_SMTP_SECURITY=tls
MOODLE_NOREPLY_ADDRESS=felipew3soft@gmail.com
```

O bootstrap persiste esses valores nas configuracoes `smtphosts`,
`smtpauthtype`, `smtpuser`, `smtppass`, `smtpsecure` e `noreplyaddress` do Moodle. A senha SMTP
nunca e escrita nos logs.

## Idempotencia

O fluxo pode ser executado mais de uma vez.

Comportamento esperado:

- se o servico ja existe no Compose, nao duplica;
- se o volume ja existe no Compose, nao duplica;
- se a rota ja existe no Caddyfile, nao duplica;
- o scheduler descobre automaticamente containers ativos com o label de tenant;
- se o secret ja existe, valores sensiveis existentes sao preservados;
- se o banco ja existe, o comando SQL mantem banco, usuario e grants atualizados;
- se o Moodle ja esta instalado, o entrypoint pula `install_database.php`;
- se o administrador, servico e token ja existem, o provisionamento reutiliza.

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
user=admin
release=4.5.12+ (Build: 20260616)
```

## Observacoes operacionais

- O proxy precisa ser reiniciado ou recarregado apos adicionar nova rota.
- O Compose de instituicoes referencia uma imagem pronta, portanto a tag local precisa ser rebuildada apos alteracoes na imagem Moodle.
- O token deve ser tratado como segredo e nao deve ser versionado.
- Os arquivos `secrets/*.env` sao ignorados pelo Git.
- Para producao, substitua senhas locais por secrets gerenciados e defina e-mails reais.
