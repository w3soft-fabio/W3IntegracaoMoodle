#!/bin/sh

# Faz o script encerrar imediatamente se qualquer comando retornar erro.
# Em C#, pense como uma excecao nao tratada: se algo falha, a execucao para
# em vez de continuar em um estado possivelmente inconsistente.
set -e

# Le a variavel de ambiente MOODLE_PUBLIC_PATH.
# A sintaxe ${VAR:-} significa:
#   - use o valor de VAR se ela existir e nao estiver vazia;
#   - caso contrario, use a string vazia.
#
# Esta variavel representa o "subcaminho" publico onde o Moodle sera servido.
# Exemplos:
#   MOODLE_PUBLIC_PATH=/moodle  -> site acessivel em /moodle
#   MOODLE_PUBLIC_PATH vazio    -> o script tenta descobrir pelo MOODLE_URL
public_path="${MOODLE_PUBLIC_PATH:-}"

# -z testa se a string esta vazia.
# Se MOODLE_PUBLIC_PATH nao foi informado, tentamos extrair o caminho da URL
# completa configurada em MOODLE_URL.
if [ -z "$public_path" ]; then
    # Executa um pequeno trecho PHP e captura a saida dele em public_path.
    # A forma $(comando) e parecida com chamar uma funcao e usar seu retorno,
    # mas aqui o "retorno" e tudo que o comando escreveu no stdout.
    #
    # O PHP faz:
    #   1. getenv("MOODLE_URL") le a variavel de ambiente.
    #   2. ?: "" usa string vazia se MOODLE_URL estiver ausente/falsa.
    #   3. parse_url(..., PHP_URL_PATH) pega apenas o path da URL.
    #      Ex: https://exemplo.com/moodle -> /moodle
    #   4. Se o path for valido, nao vazio e diferente de "/", imprime o path
    #      sem barra final.
    public_path="$(php -r '
        $url = getenv("MOODLE_URL") ?: "";
        $path = parse_url($url, PHP_URL_PATH);
        if ($path !== false && $path !== null && $path !== "" && $path !== "/") {
            echo rtrim($path, "/");
        }
    ')"
fi

# -n testa se a string NAO esta vazia.
# Este bloco so roda se temos um caminho publico util e ele nao e "/".
# Quando o caminho e "/", nao precisamos criar Alias no Apache, porque o
# Moodle ja esta sendo servido diretamente na raiz do virtual host.
if [ -n "$public_path" ] && [ "$public_path" != "/" ]; then
    # Garante que o caminho comece com "/".
    #
    # case em shell e semelhante a um switch de C#, mas usando padroes de texto:
    #   /*) combina com qualquer string que ja comece com "/".
    #   *)  combina com qualquer outra coisa.
    #
    # O comando ":" e um "no-op": nao faz nada e retorna sucesso.
    case "$public_path" in
        /*) ;;
        *) public_path="/$public_path" ;;
    esac

    # Valida o caminho para evitar caracteres inesperados na configuracao
    # gerada do Apache.
    #
    # O padrao *[!A-Za-z0-9/_-]* significa:
    #   - qualquer texto antes;
    #   - pelo menos um caractere que NAO esteja na lista permitida;
    #   - qualquer texto depois.
    #
    # Permitidos: letras, numeros, "/", "_" e "-".
    # Se encontrar algo fora disso, escreve o erro no stderr com >&2 e sai
    # com codigo 1, indicando falha para o Docker.
    case "$public_path" in
        *[!A-Za-z0-9/_-]*)
            echo "Invalid MOODLE public path: $public_path" >&2
            exit 1
            ;;
    esac

    # Cria um arquivo de configuracao do Apache.
    #
    # cat > arquivo <<EOF e um heredoc:
    #   - tudo entre <<EOF e EOF vira entrada do cat;
    #   - o operador > grava essa entrada no arquivo, substituindo o conteudo.
    #
    # Como o marcador EOF nao esta entre aspas, variaveis como ${public_path}
    # sao interpoladas antes de gravar o arquivo.
    #
    # Os Alias dizem ao Apache:
    #   /moodle   -> servir arquivos de /var/www/html
    #   /moodle/  -> servir arquivos de /var/www/html/
    #
    # O bloco Directory libera o acesso ao diretorio do Moodle e permite que
    # regras em .htaccess funcionem via AllowOverride All.
    cat > /etc/apache2/conf-enabled/moodle-public-path.conf <<EOF
Alias ${public_path} /var/www/html
Alias ${public_path}/ /var/www/html/

<Directory /var/www/html>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
fi

# Substitui o processo atual por docker-php-entrypoint, passando todos os
# argumentos recebidos por este script.
#
# "$@" preserva os argumentos exatamente como chegaram, inclusive espacos.
# exec e importante em containers: o processo final vira o PID 1, recebe sinais
# corretamente, e o Docker consegue parar o servico de forma limpa.
exec docker-php-entrypoint "$@"
