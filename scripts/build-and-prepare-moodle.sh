#!/bin/sh
# Executa este arquivo com o interpretador POSIX `sh`. Pense nele como o
# runtime deste pequeno programa: ele evita recursos exclusivos do Bash para
# que o script seja portátil entre ambientes.

# Ativa duas proteções: `-e` encerra ao falhar um comando (como uma exceção não
# tratada em C#) e `-u` transforma uma variável indefinida em erro, em vez de
# usá-la silenciosamente como texto vazio. Por exemplo, se a variável $var estiver
# indefinida e você usar `$var`, o script será encerrado.
set -eu

# `$#` é a quantidade de argumentos recebidos. '-ne' é um operador de comparação
# que verifica se dois valores são diferentes. São exigidos dois, por exemplo:
# `./build-and-prepare-moodle.sh 4.5.1 refs/tags/v4.5.1`.
if [ "$#" -ne 2 ]; then
    # `>&2` envia a mensagem para stderr, equivalente a Console.Error.WriteLine.
    printf '%s\n' "Usage: $0 <release-id> <moodle-git-ref>" >&2
    # Código 2 representa uso inválido da linha de comando.
    exit 2
fi

# `$1` e `$2` são os argumentos posicionais. As aspas preservam cada valor
# como uma única unidade, mesmo diante de caracteres especiais ou espaços.
release_id="$1"
moodle_ref="$2"

# `case` é o equivalente a um switch com padrões. Este padrão rejeita qualquer
# caractere que não seja letra, número, ponto, sublinhado ou hífen; `''` rejeita
# também uma string vazia.
case "$release_id" in
    *[!A-Zaz0--9._-]*|'')
        printf '%s\n' "Invalid release id." >&2
        exit 2
        ;;
esac

# Referências Git podem conter `/`, por isso a lista permitida é maior aqui.
# A validação mais restritiva abaixo ainda limitará os formatos aceitos.
case "$moodle_ref" in
    *[!A-Za-z0-9._/-]*|'')
        printf '%s\n' "Invalid Moodle git ref." >&2
        exit 2
        ;;
esac

# Aceita apenas um commit imutável de 40 dígitos hexadecimais ou uma tag
# explícita `refs/tags/...`. `grep -q` só retorna sucesso/falha; `!` inverte o
# resultado, logo o bloco roda se a expressão regular NÃO corresponder.
if ! printf '%s\n' "$moodle_ref" | grep -Eq '^([0-9a-fA-F]{40}|refs/tags/[A-Za-z0-9][A-Za-z0-9._/-]*)$'; then
    printf '%s\n' "Moodle ref must be a 40-character commit or an explicit refs/tags/... value." >&2
    exit 2
fi

# Calcula a pasta deste script independentemente de onde ele foi chamado.
# `dirname` remove o nome do arquivo, `cd ... && pwd` gera o caminho absoluto e
# `CDPATH=` impede uma configuração pessoal do shell de poluir essa saída.
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# Sobe de `scripts/` para a raiz do projeto.
project_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
# Monta a tag Docker, semelhante a `$"w3soft/moodle:{releaseId}"` em C#.
image="w3soft/moodle:$release_id"

# Torna a raiz do projeto a base de todos os caminhos relativos seguintes.
cd "$project_root"
# Cria diretórios necessários de modo idempotente, como Directory.CreateDirectory.
mkdir -p .provisioner generated/instituicoes proxy/tenants secrets

# Não sobrescreve uma imagem já existente. `inspect` retorna sucesso quando ela
# existe; `>/dev/null 2>&1` descarta tanto a saída normal quanto mensagens de erro.
if docker image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "Image tag already exists and will not be overwritten: $image" >&2
    exit 1
fi

# Valida o Compose antes de alterar a infraestrutura: detecta erros de sintaxe
# e de resolução de variáveis sem iniciar contêineres.
docker compose -f docker-compose.infra.yml config >/dev/null
# Inicia em segundo plano (`-d`) somente os serviços de infraestrutura.
docker compose -f docker-compose.infra.yml up -d
# Cria a imagem usando `./moodle` como contexto. O argumento de build é lido
# pelo Dockerfile para buscar a revisão Moodle solicitada; `-t` aplica a tag.
docker build --build-arg "MOODLE_REF=$moodle_ref" -t "$image" ./moodle
# Confirma que o build produziu a imagem antes de registrar o novo estado.
docker image inspect "$image" >/dev/null

# Grava primeiro em arquivo temporário no mesmo diretório. Assim, o `mv` abaixo
# é atômico: quem lê o estado vê a versão anterior ou a completa, nunca metade.
temporary=".provisioner/current-image.tmp"
printf '%s\n' "$image" > "$temporary"
# Permissão 600: apenas o usuário dono pode ler ou alterar esse arquivo.
chmod 600 "$temporary"
# Renomeia o temporário para o arquivo de estado oficial.
mv "$temporary" .provisioner/current-image

# Confirma o sucesso na saída padrão, útil também a ferramentas de automação.
printf '%s\n' "Prepared Moodle image: $image"
