#!/bin/sh

# Interrompe o script em duas situacoes importantes:
# - `-e`: se um comando falhar, o script para imediatamente.
# - `-u`: se uma variavel nao definida for usada, isso vira erro.
# Em C#, pense nisso como evitar continuar executando depois de uma excecao
# ou depois de acessar uma configuracao obrigatoria que nao existe.
set -eu

# Constantes usadas pelo restante do script. Em shell nao existe `const`, entao
# a convencao e declarar variaveis em maiusculas quando elas representam
# configuracoes globais.
MOODLE_DIR="/var/www/html"
MOODLE_DEFAULT_DATAROOT="/var/www/moodledata"
MOODLE_DB_PREFIX="mdl_"

# Escreve mensagens padronizadas no stdout. O `$*` representa todos os
# argumentos recebidos pela funcao, concatenados em uma unica string.
log() {
    printf '%s\n' "[moodle-entrypoint] $*"
}

# Escreve uma mensagem de erro no stderr (`>&2`) e finaliza o script com codigo
# 1. Isso e parecido com lancar uma excecao fatal em uma aplicacao console.
fail() {
    printf '%s\n' "[moodle-entrypoint] ERROR: $*" >&2
    exit 1
}

# Define um valor padrao para uma variavel de ambiente quando ela esta vazia.
#
# Exemplo: `env_default MOODLE_ADMIN_USER "admin"` olha se a variavel
# `MOODLE_ADMIN_USER` ja veio do Docker/Compose. Se nao veio, exporta o valor
# "admin".
#
# O `eval` e usado porque o nome da variavel esta dentro de outra variavel
# (`name`). Isso permite ler dinamicamente algo como `$MOODLE_ADMIN_USER`.
env_default() {
    name="$1"
    default="$2"
    eval "value=\${$name:-}"

    if [ -z "$value" ]; then
        export "$name=$default"
    fi
}

# Garante que uma variavel de ambiente obrigatoria foi informada. Se a variavel
# estiver vazia ou nao existir, o script para com `fail`.
require_env() {
    name="$1"
    eval "value=\${$name:-}"

    if [ -z "$value" ]; then
        fail "Missing required environment variable: $name"
    fi
}

# Executa um comando como usuario `www-data`, que e o usuario usado pelo Apache
# dentro da imagem PHP. Isso evita criar arquivos do Moodle como root.
run_as_www_data() {
    runuser -u www-data -- "$@"
}

# Executa uma query no MariaDB usando as variaveis de ambiente do Moodle.
#
# Opcoes relevantes:
# - `--ssl=0`: desativa SSL para a conexao local/rede interna.
# - `-h`, `-u`, `-p`: host, usuario e senha.
# - `-N -B`: retorna saida sem cabecalho e em formato simples, mais facil de
#   comparar em shell.
# - `-e "$1"`: executa a query recebida como primeiro argumento da funcao.
mariadb_query() {
    mariadb \
        --ssl=0 \
        -h "$MOODLE_DB_HOST" \
        -u "$MOODLE_DB_USER" \
        "-p$MOODLE_DB_PASSWORD" \
        "$MOODLE_DB_NAME" \
        -N -B \
        -e "$1"
}

# Aguarda o banco ficar disponivel antes de tentar instalar/atualizar o Moodle.
# Em containers, e comum o container da aplicacao iniciar antes do banco estar
# pronto para aceitar conexoes.
wait_for_database() {
    attempts="${MOODLE_DB_WAIT_ATTEMPTS:-60}"
    sleep_seconds="${MOODLE_DB_WAIT_SLEEP_SECONDS:-2}"
    i=1

    log "Waiting for database ${MOODLE_DB_HOST}/${MOODLE_DB_NAME}..."

    while [ "$i" -le "$attempts" ]; do
        if mariadb_query "SELECT 1;" >/dev/null 2>&1; then
            log "Database is available."
            return 0
        fi

        i=$((i + 1))
        sleep "$sleep_seconds"
    done

    fail "Database did not become available after ${attempts} attempts."
}

# Conta quantas tabelas do Moodle existem no banco atual, usando o prefixo
# configurado em `MOODLE_DB_PREFIX`. O resultado ajuda a decidir se o banco esta
# vazio, ja instalado ou em um estado inconsistente.
table_count() {
    mariadb_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE '${MOODLE_DB_PREFIX}%';"
}

# Verifica se a tabela principal de configuracao do Moodle existe. A presenca
# de `${MOODLE_DB_PREFIX}config` e usada como sinal de que a instalacao do
# Moodle ja foi concluida anteriormente.
config_table_exists() {
    count="$(mariadb_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '${MOODLE_DB_PREFIX}config';")"
    [ "$count" = "1" ]
}

# Configura o Apache para servir o Moodle em um caminho publico especifico,
# por exemplo `/moodle`, em vez de apenas na raiz do dominio.
configure_public_path() {
    public_path="${MOODLE_PUBLIC_PATH:-}"

    # Se `MOODLE_PUBLIC_PATH` nao foi informado explicitamente, tenta extrair o
    # caminho a partir de `MOODLE_URL`. O PHP e usado aqui porque ele ja tem
    # `parse_url`, evitando fazer parsing manual de URL em shell.
    if [ -z "$public_path" ]; then
        public_path="$(php -r '
            $url = getenv("MOODLE_URL") ?: "";
            $path = parse_url($url, PHP_URL_PATH);
            if ($path !== false && $path !== null && $path !== "" && $path !== "/") {
                echo rtrim($path, "/");
            }
        ')"
    fi

    if [ -n "$public_path" ] && [ "$public_path" != "/" ]; then
        # Garante que o caminho comece com `/`. O `case` em shell funciona como
        # um `switch` simples, com padroes em vez de expressoes booleanas.
        case "$public_path" in
            /*) ;;
            *) public_path="/$public_path" ;;
        esac

        # Aceita apenas letras, numeros, barra, underline e hifen. Isso evita
        # gravar uma configuracao Apache invalida ou perigosa.
        case "$public_path" in
            *[!A-Za-z0-9/_-]*)
                fail "Invalid MOODLE public path: $public_path"
                ;;
        esac

        # Cria um arquivo de configuracao do Apache usando um heredoc. Tudo entre
        # `<<EOF` e `EOF` e escrito no arquivo, com interpolacao das variaveis do
        # shell, como `${public_path}`.
        cat > /etc/apache2/conf-enabled/moodle-public-path.conf <<EOF
Alias ${public_path}/ /var/www/html/
Alias ${public_path} /var/www/html

<Directory /var/www/html>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
    fi
}

# Define valores padrao para variaveis que podem ser omitidas no ambiente.
# Esses defaults permitem inicializar o Moodle com uma configuracao previsivel,
# mas ainda deixam o Docker/Compose sobrescrever cada valor quando necessario.
set_bootstrap_defaults() {
    env_default MOODLE_AUTO_BOOTSTRAP "1"
    env_default MOODLE_DATAROOT "$MOODLE_DEFAULT_DATAROOT"
    env_default MOODLE_ADMIN_USER "admin"
    env_default MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL "1"
    env_default MOODLE_WS_SERVICE_NAME "W3Soft Student Sync"
    env_default MOODLE_WS_SERVICE_SHORTNAME "w3soft_student_sync"
    env_default MOODLE_WS_FUNCTIONS "core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_course_get_categories,core_course_create_categories,core_course_update_categories,core_course_create_courses,core_course_update_courses,core_user_get_users,core_user_get_users_by_field,core_user_create_users,core_user_update_users,core_cohort_create_cohorts,core_cohort_add_cohort_members,core_cohort_delete_cohort_members,enrol_manual_enrol_users,enrol_manual_unenrol_users,core_grades_update_grades,core_calendar_create_calendar_events,local_w3sync_publicar_conteudos"
    env_default MOODLE_WS_ROLE_SHORTNAME "w3soft_ws_integration"
    env_default MOODLE_WS_TOKEN_FILE "$MOODLE_DATAROOT/w3soft/ws-token.txt"
    env_default MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME "student"
    env_default MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAMES "student,editingteacher"
    env_default MOODLE_WS_EXTRA_CAPABILITIES "moodle/course:create,moodle/course:update,moodle/category:manage,moodle/cohort:manage,moodle/role:assign,moodle/grade:edit,moodle/course:manageactivities,mod/assign:grade,moodle/calendar:manageentries"
}

# Valida todas as variaveis obrigatorias para o bootstrap automatico. A ideia e
# falhar cedo, com uma mensagem clara, antes de rodar instaladores ou alterar o
# banco de dados.
validate_bootstrap_environment() {
    require_env MOODLE_URL
    require_env MOODLE_DB_HOST
    require_env MOODLE_DB_NAME
    require_env MOODLE_DB_USER
    require_env MOODLE_DB_PASSWORD
    require_env MOODLE_DATAROOT

    require_env MOODLE_SITE_FULLNAME
    require_env MOODLE_SITE_SHORTNAME
    require_env MOODLE_SUPPORT_EMAIL

    require_env MOODLE_ADMIN_USER
    require_env MOODLE_ADMIN_PASSWORD
    require_env MOODLE_ADMIN_FIRSTNAME
    require_env MOODLE_ADMIN_LASTNAME
    require_env MOODLE_ADMIN_EMAIL
    require_env MOODLE_ADMIN_CITY
    require_env MOODLE_ADMIN_COUNTRY
    require_env MOODLE_ADMIN_TIMEZONE

    require_env MOODLE_WS_SERVICE_NAME
    require_env MOODLE_WS_SERVICE_SHORTNAME
    require_env MOODLE_WS_FUNCTIONS
    require_env MOODLE_WS_USER_USERNAME
    require_env MOODLE_WS_USER_PASSWORD
    require_env MOODLE_WS_USER_FIRSTNAME
    require_env MOODLE_WS_USER_LASTNAME
    require_env MOODLE_WS_USER_EMAIL
    require_env MOODLE_WS_USER_CITY
    require_env MOODLE_WS_USER_COUNTRY
    require_env MOODLE_WS_USER_TIMEZONE
    require_env MOODLE_WS_ROLE_SHORTNAME
    require_env MOODLE_WS_TOKEN_FILE
    require_env MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME
    require_env MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAMES
}

# Fluxo principal de inicializacao automatica do Moodle.
#
# Ele roda apenas quando:
# - `MOODLE_AUTO_BOOTSTRAP` nao foi desativado; e
# - o comando principal do container e `apache2-foreground`.
#
# Isso evita executar instalacao/upgrade quando o container e usado para outro
# comando, como abrir um shell ou rodar uma tarefa administrativa.
bootstrap_moodle() {
    case "${MOODLE_AUTO_BOOTSTRAP:-1}" in
        0|false|FALSE|no|NO)
            log "Automatic Moodle bootstrap disabled."
            return 0
            ;;
    esac

    if [ "${1:-}" != "apache2-foreground" ]; then
        log "Skipping automatic Moodle bootstrap for command: ${1:-}"
        return 0
    fi

    set_bootstrap_defaults
    validate_bootstrap_environment

    # Garante que o diretorio de dados exista e pertenca ao usuario do Apache.
    # O Moodle grava arquivos enviados, caches e outros dados nesse caminho.
    mkdir -p "$MOODLE_DATAROOT"
    chown www-data:www-data "$MOODLE_DATAROOT"

    wait_for_database

    # `first_install` comeca como 0 e vira 1 somente quando este container esta
    # instalando o Moodle em um banco vazio pela primeira vez.
    first_install=0
    if config_table_exists; then
        log "Moodle database is already installed."
    else
        existing_tables="$(table_count)"

        # Se existem tabelas com prefixo do Moodle, mas a tabela config nao
        # existe, o banco provavelmente ficou com uma instalacao incompleta.
        # Nesse caso o script para para evitar sobrescrever ou piorar o estado.
        if [ "$existing_tables" != "0" ]; then
            fail "Database has Moodle tables but ${MOODLE_DB_PREFIX}config is missing. Refusing to continue because the install looks incomplete."
        fi

        first_install=1
        log "Moodle database is empty. Running non-interactive installation."

        # Executa o instalador CLI do Moodle sem interacao humana. Cada opcao
        # `--nome=valor` preenche um dado que normalmente seria pedido pela tela
        # de instalacao web.
        run_as_www_data php "$MOODLE_DIR/admin/cli/install_database.php" \
            "--lang=${MOODLE_DEFAULT_LANG:-pt_br}" \
            "--adminuser=$MOODLE_ADMIN_USER" \
            "--adminpass=$MOODLE_ADMIN_PASSWORD" \
            "--adminemail=$MOODLE_ADMIN_EMAIL" \
            "--fullname=$MOODLE_SITE_FULLNAME" \
            "--shortname=$MOODLE_SITE_SHORTNAME" \
            "--summary=${MOODLE_SITE_SUMMARY:-}" \
            "--supportemail=$MOODLE_SUPPORT_EMAIL" \
            --agree-license

        log "Moodle database installation finished."
    fi

    # Exporta uma flag para processos filhos. O script PHP de provisionamento
    # pode usar isso para saber se esta rodando logo apos a primeira instalacao.
    export MOODLE_BOOTSTRAP_FIRST_INSTALL="$first_install"

    # O upgrade CLI e idempotente: se nao houver nada para atualizar, ele apenas
    # confirma que o banco esta na versao esperada. Se houver atualizacoes do
    # Moodle, aplica sem pedir confirmacao.
    log "Running Moodle CLI upgrade check."
    run_as_www_data php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive

    # Roda o provisionamento customizado do projeto, como criacao/configuracao
    # de servico web, usuario de integracao, permissoes e token.
    log "Running tenant provisioning."
    run_as_www_data php "$MOODLE_DIR/bootstrap/provision.php"

    log "Automatic Moodle bootstrap finished."
}

# Antes de iniciar o processo principal do container, prepara o Apache e executa
# o bootstrap do Moodle quando aplicavel.
configure_public_path
bootstrap_moodle "${1:-}"

# Substitui o processo atual pelo entrypoint oficial da imagem PHP. O `exec`
# e importante em containers porque faz o processo final receber sinais do
# Docker corretamente, como SIGTERM durante `docker stop`.
exec docker-php-entrypoint "$@"
