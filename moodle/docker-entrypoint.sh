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

# Garante que uma variavel de ambiente obrigatoria foi informada. Se a variavel
# estiver vazia ou nao existir, o script para com `fail`.
require_env() {
    name="$1"
    eval "value=\${$name:-}"

    if [ -z "$value" ]; then
        fail "Missing required environment variable: $name"
    fi
}

# Exige que a variavel exista, mas permite valor vazio quando vazio possui
# significado explicito (por exemplo SMTP sem TLS ou BBB sem credenciais).
require_env_defined() {
    name="$1"
    eval "is_defined=\${$name+x}"

    if [ -z "$is_defined" ]; then
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

# Considera a instalacao completa somente quando um conjunto minimo de tabelas
# estruturais existe. Encontrar apenas parte dele deve ser tratado como banco
# parcial, nunca como instalacao valida.
moodle_installation_complete() {
    count="$(mariadb_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN ('${MOODLE_DB_PREFIX}config', '${MOODLE_DB_PREFIX}course', '${MOODLE_DB_PREFIX}user');")"
    [ "$count" = "3" ]
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

# Valida todas as variaveis obrigatorias para o bootstrap explicito. A ideia e
# falhar cedo, com uma mensagem clara, antes de rodar instaladores ou alterar o
# banco de dados.
validate_bootstrap_environment() {
    require_env MOODLE_URL
    require_env MOODLE_DB_HOST
    require_env MOODLE_DB_NAME
    require_env MOODLE_DB_USER
    require_env MOODLE_DB_PASSWORD
    require_env MOODLE_DATAROOT
    require_env MOODLE_DEFAULT_LANG
    require_env MOODLE_AUTO_DETECT_LANG
    require_env MOODLE_FORCE_LOGIN
    require_env MOODLE_W3_DATABASE

    require_env MOODLE_SITE_FULLNAME
    require_env MOODLE_SITE_SHORTNAME
    require_env_defined MOODLE_SITE_SUMMARY
    require_env MOODLE_SUPPORT_EMAIL

    require_env MOODLE_ADMIN_USER
    require_env MOODLE_ADMIN_PASSWORD
    require_env MOODLE_ADMIN_FIRSTNAME
    require_env MOODLE_ADMIN_LASTNAME
    require_env MOODLE_ADMIN_EMAIL
    require_env MOODLE_ADMIN_CITY
    require_env MOODLE_ADMIN_COUNTRY
    require_env MOODLE_ADMIN_TIMEZONE
    require_env MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL

    require_env MOODLE_BBB_ENABLED
    require_env MOODLE_BBB_RECORDING_DEFAULT
    require_env_defined MOODLE_BBB_SERVER_URL
    require_env_defined MOODLE_BBB_SHARED_SECRET
    require_env MOODLE_BBB_CHECKSUM_ALGORITHM

    require_env MOODLE_SMTP_HOST
    require_env MOODLE_SMTP_AUTH_TYPE
    require_env MOODLE_SMTP_USER
    require_env MOODLE_SMTP_PASSWORD
    require_env_defined MOODLE_SMTP_SECURITY
    require_env MOODLE_NOREPLY_ADDRESS

    require_env MOODLE_ENROL_MANUAL_ENABLED
    require_env MOODLE_ENROL_MANUAL_ROLE_ID

    require_env MOODLE_WS_SERVICE_NAME
    require_env MOODLE_WS_SERVICE_SHORTNAME
    require_env MOODLE_WS_FUNCTIONS
    require_env MOODLE_WS_TOKEN_FILE
}

# Fluxo de bootstrap invocado somente pelo comando administrativo
# `moodle-bootstrap install|reconcile|upgrade`.
bootstrap_moodle() {
    mode="${1:-}"
    case "$mode" in
        install|reconcile|upgrade) ;;
        *) fail "Usage: moodle-bootstrap install|reconcile|upgrade" ;;
    esac

    validate_bootstrap_environment

    # Garante que o diretorio de dados exista e pertenca ao usuario do Apache.
    # O Moodle grava arquivos enviados, caches e outros dados nesse caminho.
    mkdir -p "$MOODLE_DATAROOT"
    chown www-data:www-data "$MOODLE_DATAROOT"

    wait_for_database

    # `first_install` comeca como 0 e vira 1 somente quando este container esta
    # instalando o Moodle em um banco vazio pela primeira vez.
    first_install=0
    if moodle_installation_complete; then
        log "Moodle database is already installed."
    elif [ "$mode" != "install" ]; then
        fail "Moodle must be installed before running bootstrap mode: $mode"
    else
        existing_tables="$(table_count)"

        # Se existem tabelas com prefixo do Moodle, mas as tabelas estruturais
        # nao estao completas, o banco ficou com uma instalacao incompleta.
        # Nesse caso o script para para evitar sobrescrever ou piorar o estado.
        if [ "$existing_tables" != "0" ]; then
            fail "Database has Moodle tables but the required structural tables are incomplete. Refusing to continue."
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

    if [ "$mode" = "upgrade" ]; then
        log "Running explicit Moodle CLI upgrade."
        run_as_www_data php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive
    fi

    # Roda o provisionamento customizado do projeto, como criacao/configuracao
    # do servico web e do token administrativo.
    log "Running tenant provisioning."
    run_as_www_data php "$MOODLE_DIR/bootstrap/provision.php"

    log "Moodle bootstrap mode '$mode' finished."
}

configure_public_path

if [ "$(basename "$0")" = "moodle-bootstrap" ]; then
    bootstrap_moodle "${1:-}"
    exit 0
fi

# Substitui o processo atual pelo entrypoint oficial da imagem PHP. O `exec`
# e importante em containers porque faz o processo final receber sinais do
# Docker corretamente, como SIGTERM durante `docker stop`.
exec docker-php-entrypoint "$@"
