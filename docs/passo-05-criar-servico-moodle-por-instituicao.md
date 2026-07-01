# Passo 5: Criar um servico Moodle por instituicao

## Objetivo deste passo

Neste passo, o objetivo e criar containers Moodle separados para cada instituicao, usando a infraestrutura compartilhada criada nos passos anteriores.

A ideia central e:

```text
Infraestrutura compartilhada:
  moodle_db
  moodle_redis
  moodle_proxy
  moodle_net

Instituicoes:
  moodle_escola_a -> banco moodle_escola_a -> volume moodledata_escola_a
  moodle_escola_b -> banco moodle_escola_b -> volume moodledata_escola_b
```

Cada instituicao tera seu proprio container Moodle e seu proprio volume `moodledata`, mas todas usarao o mesmo MariaDB, o mesmo Redis e a mesma rede Docker.

Neste primeiro laboratorio local, vamos criar duas instituicoes:

```text
escola-a
escola-b
```

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- criar um arquivo Compose separado para aplicacoes;
- usar uma rede Docker externa criada por outro Compose;
- entender a diferenca entre `image` e `build`;
- reutilizar a mesma imagem Moodle para mais de um container;
- configurar variaveis por instituicao com `env_file`;
- criar volumes separados para dados persistentes;
- subir somente os containers Moodle das instituicoes;
- verificar se os containers estao na mesma rede da infraestrutura;
- inspecionar logs;
- executar comandos dentro de containers com `docker compose exec`;
- testar isolamento de arquivos entre volumes;
- parar containers sem apagar dados.

## Resultado esperado

Ao final deste passo, voce tera estes containers:

```text
moodle_escola_a
moodle_escola_b
```

E estes volumes:

```text
moodledata_escola_a
moodledata_escola_b
```

Os containers Moodle deverao conseguir conversar com:

```text
db
redis
```

usando a rede Docker compartilhada:

```text
moodle_net
```

## Pre-requisitos

Antes de iniciar este passo, conclua os passos anteriores:

```text
docs/passo-01-padronizar-imagem-moodle.md
docs/passo-02-configuracao-por-variaveis.md
docs/passo-03-infraestrutura-compartilhada.md
docs/passo-04-criar-bancos-e-usuarios.md
```

Arquivos que ja devem existir:

```text
docker-compose.infra.yml
moodle/Dockerfile
moodle/config.php
secrets/infra.local.env
secrets/escola-a.local.env
secrets/escola-b.local.env
proxy/Caddyfile.local
```

Bancos e usuarios que ja devem existir no MariaDB:

```text
Banco:   moodle_escola_a
Usuario: moodle_escola_a
Senha:   senha-local-escola-a

Banco:   moodle_escola_b
Usuario: moodle_escola_b
Senha:   senha-local-escola-b
```

## Conceitos rapidos antes dos comandos

### Um container Moodle por instituicao

Mesmo usando a mesma imagem Docker, cada instituicao roda em um container separado.

Exemplo:

```text
Imagem:
  w3soft/moodle:2026.07.1-local

Containers:
  moodle_escola_a
  moodle_escola_b
```

A imagem e o molde. O container e a execucao desse molde.

### Um volume `moodledata` por instituicao

O `moodledata` guarda arquivos enviados, caches locais, sessoes em arquivo quando usadas, arquivos temporarios e outros dados gerados pelo Moodle.

Cada instituicao precisa de um volume proprio:

```text
moodledata_escola_a
moodledata_escola_b
```

Assim, o container da escola A nao monta o volume da escola B.

### Um arquivo `.env` por instituicao

Cada container Moodle recebe suas configuracoes por um arquivo de ambiente.

Neste projeto ja existem:

```text
secrets/escola-a.local.env
secrets/escola-b.local.env
```

O arquivo da escola A aponta para o banco da escola A:

```text
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-local-escola-a
```

O arquivo da escola B aponta para o banco da escola B:

```text
MOODLE_DB_NAME=moodle_escola_b
MOODLE_DB_USER=moodle_escola_b
MOODLE_DB_PASSWORD=senha-local-escola-b
```

### Rede externa no Compose das instituicoes

A rede `moodle_net` e criada no arquivo `docker-compose.infra.yml`.

O arquivo das instituicoes nao deve criar outra rede com outro nome. Ele deve entrar na rede ja existente.

Por isso, no Compose das instituicoes vamos usar:

```yaml
networks:
  moodle_net:
    external: true
```

Isso significa:

```text
Docker, use a rede moodle_net que ja existe.
```

## Arquivo que sera criado

Neste passo, vamos criar:

```text
docker-compose.instituicoes.yml
```

Esse arquivo tera somente os containers Moodle das instituicoes.

Nao vamos alterar o `docker-compose.yml` original neste passo.

## Etapa 1: Entrar na pasta do projeto

Execute:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

Confirme a pasta atual:

```sh
pwd
```

Resultado esperado:

```text
/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker
```

Liste os arquivos principais:

```sh
ls
```

Resultado esperado, no minimo:

```text
docker-compose.infra.yml
docker-compose.yml
docs
moodle
proxy
secrets
```

## Etapa 2: Verificar se a infraestrutura esta rodando

Confira os containers:

```sh
docker ps
```

Procure por:

```text
moodle_db
moodle_redis
moodle_proxy
```

Se eles nao estiverem rodando, suba a infraestrutura:

```sh
docker compose -f docker-compose.infra.yml up -d
```

Verifique novamente:

```sh
docker compose -f docker-compose.infra.yml ps
```

Resultado esperado:

```text
NAME            SERVICE   STATUS
moodle_db       db        running
moodle_redis    redis     running
moodle_proxy    proxy     running
```

Se algum container estiver como `starting`, aguarde alguns segundos e rode:

```sh
docker compose -f docker-compose.infra.yml ps
```

## Etapa 3: Verificar se a rede compartilhada existe

Liste as redes Docker:

```sh
docker network ls
```

Procure pela rede:

```text
moodle_net
```

Voce tambem pode inspecionar a rede:

```sh
docker network inspect moodle_net
```

Esse comando mostra detalhes da rede e os containers conectados nela.

Neste momento, devem aparecer pelo menos:

```text
moodle_db
moodle_redis
moodle_proxy
```

## Etapa 4: Verificar se os secrets locais das instituicoes existem

Liste os arquivos da pasta `secrets`:

```sh
ls secrets
```

Confira o arquivo da escola A:

```sh
sed -n '1,80p' secrets/escola-a.local.env
```

Resultado esperado:

```text
MOODLE_URL=http://localhost:8088/i/escola-a
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-local-escola-a
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola_a
MOODLE_TENANT_ID=escola-a-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

Confira o arquivo da escola B:

```sh
sed -n '1,80p' secrets/escola-b.local.env
```

Resultado esperado:

```text
MOODLE_URL=http://localhost:8088/i/escola-b
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_b
MOODLE_DB_USER=moodle_escola_b
MOODLE_DB_PASSWORD=senha-local-escola-b
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola_b
MOODLE_TENANT_ID=escola-b-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_b_
```

Se algum arquivo nao existir, volte ao Passo 2 e crie os arquivos de configuracao por variaveis.

## Etapa 5: Verificar se a imagem Moodle local existe

Liste as imagens Docker relacionadas ao Moodle:

```sh
docker images
```

Procure por:

```text
w3soft/moodle   2026.06.1-local
```

Se a imagem ainda nao existir, construa a imagem local usando o Compose atual:

```sh
docker compose build moodle
```

Depois confira novamente:

```sh
docker images w3soft/moodle
```

Resultado esperado:

```text
REPOSITORY       TAG                 IMAGE ID       CREATED
w3soft/moodle    2026.06.1-local     ...
```

Observacao: se esta for a primeira vez que voce constroi a imagem, o Docker pode baixar pacotes e clonar o Moodle. Isso pode demorar.

## Etapa 6: Criar o arquivo `docker-compose.instituicoes.yml`

Crie o arquivo:

```sh
touch docker-compose.instituicoes.yml
```

Abra o arquivo no seu editor preferido e adicione este conteudo:

```yaml
services:
  moodle_escola_a:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_a
    restart: unless-stopped
    env_file:
      - ./secrets/escola-a.local.env
    volumes:
      - moodledata_escola_a:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

  moodle_escola_b:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_b
    restart: unless-stopped
    env_file:
      - ./secrets/escola-b.local.env
    volumes:
      - moodledata_escola_b:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_a:
    name: moodledata_escola_a
  moodledata_escola_b:
    name: moodledata_escola_b

networks:
  moodle_net:
    external: true
```

Se quiser criar o arquivo pelo terminal, use:

```sh
cat > docker-compose.instituicoes.yml <<'YAML'
services:
  moodle_escola_a:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_a
    restart: unless-stopped
    env_file:
      - ./secrets/escola-a.local.env
    volumes:
      - moodledata_escola_a:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

  moodle_escola_b:
    image: w3soft/moodle:2026.07.1-local
    container_name: moodle_escola_b
    restart: unless-stopped
    env_file:
      - ./secrets/escola-b.local.env
    volumes:
      - moodledata_escola_b:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_a:
    name: moodledata_escola_a
  moodledata_escola_b:
    name: moodledata_escola_b

networks:
  moodle_net:
    external: true
YAML
```

## Etapa 7: Entender o arquivo criado

### `services`

Cada item dentro de `services` representa um container que o Compose pode criar.

Neste arquivo temos:

```yaml
services:
  moodle_escola_a:
  moodle_escola_b:
```

Isso significa:

```text
Crie um container para a escola A.
Crie um container para a escola B.
```

### `image`

```yaml
image: w3soft/moodle:2026.07.1-local
```

Os dois containers usam a mesma imagem.

Isso e importante porque voce padroniza:

- versao do Moodle;
- versao do PHP;
- extensoes PHP;
- plugins;
- `config.php`;
- `php.ini`.

### `container_name`

```yaml
container_name: moodle_escola_a
```

Define o nome real do container no Docker.

Isso facilita comandos como:

```sh
docker exec moodle_escola_a php -v
```

### `env_file`

```yaml
env_file:
  - ./secrets/escola-a.local.env
```

Carrega variaveis de ambiente para dentro do container.

O `moodle/config.php` le essas variaveis com `getenv`.

### `volumes`

```yaml
volumes:
  - moodledata_escola_a:/var/www/moodledata
```

Monta o volume persistente da escola A dentro do container.

Dentro do container, o Moodle sempre enxerga:

```text
/var/www/moodledata
```

Mas no Docker, a escola A e a escola B usam volumes diferentes.

### `networks`

```yaml
networks:
  - moodle_net
```

Conecta o container Moodle na mesma rede da infraestrutura.

Assim, o Moodle consegue acessar o banco por:

```text
db
```

e o Redis por:

```text
redis
```

### `cpus`, `mem_limit` e `mem_reservation`

```yaml
cpus: "1.0"
mem_limit: 1.5g
mem_reservation: 512m
```

Essas opcoes ajudam a limitar consumo de recursos por instituicao.

Significado:

- `cpus: "1.0"`: permite usar ate aproximadamente 1 CPU;
- `mem_limit: 1.5g`: limite maximo de memoria;
- `mem_reservation: 512m`: reserva/referencia inicial de memoria.

Esses valores sao bons para laboratorio local. Em producao, ajuste com base em metricas.

## Etapa 8: Validar a sintaxe do Compose

Rode:

```sh
docker compose -f docker-compose.instituicoes.yml config
```

Esse comando nao sobe containers. Ele apenas interpreta o arquivo e mostra a configuracao final.

Se houver erro de espaco, indentacao ou chave invalida, o Docker Compose vai mostrar uma mensagem.

Resultado esperado:

```text
services:
  moodle_escola_a:
    ...
  moodle_escola_b:
    ...
networks:
  moodle_net:
    external: true
volumes:
  moodledata_escola_a:
    name: moodledata_escola_a
  moodledata_escola_b:
    name: moodledata_escola_b
```

## Etapa 9: Subir os containers Moodle das instituicoes

Suba os containers:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

O `-d` significa modo destacado, ou seja, os containers ficam rodando em segundo plano.

Verifique o status:

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

Resultado esperado:

```text
NAME              SERVICE           STATUS
moodle_escola_a   moodle_escola_a   running
moodle_escola_b   moodle_escola_b   running
```

Tambem confira com:

```sh
docker ps
```

Agora voce deve ver:

```text
moodle_db
moodle_redis
moodle_proxy
moodle_escola_a
moodle_escola_b
```

## Etapa 10: Verificar logs dos containers Moodle

Veja os logs da escola A:

```sh
docker logs moodle_escola_a
```

Veja os logs da escola B:

```sh
docker logs moodle_escola_b
```

Se quiser acompanhar logs em tempo real:

```sh
docker logs -f moodle_escola_a
```

Para sair do acompanhamento em tempo real, pressione:

```text
Ctrl+C
```

Resultado esperado: nao deve aparecer erro sobre variaveis ausentes como:

```text
Missing required environment variable
```

Se aparecer esse erro, confira o arquivo `.env` da instituicao correspondente.

## Etapa 11: Verificar se os containers entraram na rede `moodle_net`

Inspecione a rede:

```sh
docker network inspect moodle_net
```

Procure na saida por:

```text
moodle_escola_a
moodle_escola_b
```

Agora a rede deve conter:

```text
moodle_db
moodle_redis
moodle_proxy
moodle_escola_a
moodle_escola_b
```

## Etapa 12: Testar comandos dentro de cada Moodle

Execute:

```sh
docker exec moodle_escola_a php -v
```

Resultado esperado:

```text
PHP 8.3...
```

Execute tambem:

```sh
docker exec moodle_escola_b php -v
```

Verifique se o arquivo `config.php` existe dentro de cada container:

```sh
docker exec moodle_escola_a ls -l /var/www/html/config.php
```

```sh
docker exec moodle_escola_b ls -l /var/www/html/config.php
```

Verifique se o `moodledata` existe:

```sh
docker exec moodle_escola_a ls -ld /var/www/moodledata
```

```sh
docker exec moodle_escola_b ls -ld /var/www/moodledata
```

## Etapa 13: Testar variaveis de ambiente dentro dos containers

Veja o banco configurado para a escola A:

```sh
docker exec moodle_escola_a printenv MOODLE_DB_NAME
```

Resultado esperado:

```text
moodle_escola_a
```

Veja o banco configurado para a escola B:

```sh
docker exec moodle_escola_b printenv MOODLE_DB_NAME
```

Resultado esperado:

```text
moodle_escola_b
```

Confira a URL da escola A:

```sh
docker exec moodle_escola_a printenv MOODLE_URL
```

Resultado esperado:

```text
http://localhost:8088/i/escola-a
```

Confira a URL da escola B:

```sh
docker exec moodle_escola_b printenv MOODLE_URL
```

Resultado esperado:

```text
http://localhost:8088/i/escola-b
```

## Etapa 14: Testar acesso ao banco a partir de cada Moodle

O container Moodle possui o cliente MariaDB instalado pela imagem.

Teste a escola A:

```sh
docker exec moodle_escola_a mariadb -h db -u moodle_escola_a -psenha-local-escola-a -e "SELECT DATABASE();" moodle_escola_a
```

Resultado esperado:

```text
DATABASE()
moodle_escola_a
```

Teste a escola B:

```sh
docker exec moodle_escola_b mariadb -h db -u moodle_escola_b -psenha-local-escola-b -e "SELECT DATABASE();" moodle_escola_b
```

Resultado esperado:

```text
DATABASE()
moodle_escola_b
```

Agora teste o isolamento. O usuario da escola A nao deve acessar o banco da escola B:

```sh
docker exec moodle_escola_a mariadb -h db -u moodle_escola_a -psenha-local-escola-a -e "SHOW TABLES;" moodle_escola_b
```

Resultado esperado:

```text
ERROR 1044 ... Access denied
```

Esse erro e bom nesse teste. Ele mostra que o usuario de uma instituicao nao acessa o banco da outra.

## Etapa 15: Testar acesso ao Redis a partir dos containers

Neste momento, o `config.php` ainda pode nao estar usando Redis como cache/sessao. Mesmo assim, ja podemos testar conectividade de rede.

Como a imagem Moodle atual nao instala necessariamente `redis-cli`, use o container do Redis para testar se ele esta respondendo:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

Confira as variaveis Redis da escola A:

```sh
docker exec moodle_escola_a printenv MOODLE_REDIS_HOST
```

```sh
docker exec moodle_escola_a printenv MOODLE_REDIS_PREFIX
```

Resultado esperado:

```text
redis
escola_a_
```

Confira as variaveis Redis da escola B:

```sh
docker exec moodle_escola_b printenv MOODLE_REDIS_HOST
```

```sh
docker exec moodle_escola_b printenv MOODLE_REDIS_PREFIX
```

Resultado esperado:

```text
redis
escola_b_
```

O uso efetivo desses prefixos no Moodle sera tratado no Passo 6.

## Etapa 16: Testar isolamento dos volumes `moodledata`

Crie um arquivo de teste dentro do `moodledata` da escola A:

```sh
docker exec moodle_escola_a sh -c "echo escola-a > /var/www/moodledata/teste-isolamento.txt"
```

Leia o arquivo na escola A:

```sh
docker exec moodle_escola_a cat /var/www/moodledata/teste-isolamento.txt
```

Resultado esperado:

```text
escola-a
```

Agora tente ler o mesmo caminho na escola B:

```sh
docker exec moodle_escola_b sh -c "cat /var/www/moodledata/teste-isolamento.txt || true"
```

Resultado esperado:

```text
cat: /var/www/moodledata/teste-isolamento.txt: No such file or directory
```

Isso confirma que a escola B nao esta usando o mesmo volume `moodledata` da escola A.

Crie tambem um arquivo no volume da escola B:

```sh
docker exec moodle_escola_b sh -c "echo escola-b > /var/www/moodledata/teste-isolamento.txt"
```

Leia na escola B:

```sh
docker exec moodle_escola_b cat /var/www/moodledata/teste-isolamento.txt
```

Resultado esperado:

```text
escola-b
```

Leia novamente na escola A:

```sh
docker exec moodle_escola_a cat /var/www/moodledata/teste-isolamento.txt
```

Resultado esperado:

```text
escola-a
```

Mesmo caminho dentro do container, mas volumes diferentes no Docker.

## Etapa 17: Verificar os volumes criados

Liste os volumes Docker:

```sh
docker volume ls
```

Procure por:

```text
moodledata_escola_a
moodledata_escola_b
```

Inspecione o volume da escola A:

```sh
docker volume inspect moodledata_escola_a
```

Inspecione o volume da escola B:

```sh
docker volume inspect moodledata_escola_b
```

Esses comandos mostram metadados do volume, incluindo o ponto onde o Docker armazena os dados internamente.

## Etapa 18: Testar HTTP direto dos containers

O arquivo `docker-compose.instituicoes.yml` nao publica portas no host.

Isso significa que voce nao acessa os Moodles diretamente por:

```text
http://localhost:alguma-porta
```

Eles devem ser acessados via proxy compartilhado no Passo 7.

Mesmo assim, podemos testar se o Apache esta respondendo dentro da rede Docker usando um container temporario `curl`.

Execute:

```sh
docker run --rm --network moodle_net curlimages/curl:8.8.0 -I http://moodle_escola_a
```

Resultado esperado:

```text
HTTP/1.1 303 See Other
```

ou:

```text
HTTP/1.1 200 OK
```

Teste a escola B:

```sh
docker run --rm --network moodle_net curlimages/curl:8.8.0 -I http://moodle_escola_b
```

Resultado esperado:

```text
HTTP/1.1 303 See Other
```

ou:

```text
HTTP/1.1 200 OK
```

Se o Docker precisar baixar a imagem `curlimages/curl`, esse comando pode demorar na primeira execucao.

Alternativa sem baixar imagem extra:

```sh
docker exec moodle_escola_a curl -I http://localhost
```

```sh
docker exec moodle_escola_b curl -I http://localhost
```

## Etapa 19: Entender por que ainda nao acessamos pelo navegador

Neste passo, criamos os containers Moodle por instituicao.

Mas o `proxy/Caddyfile.local` ainda esta com uma resposta simples:

```caddyfile
:80 {
    respond "Proxy local da infraestrutura Moodle funcionando" 200
}
```

Por isso, ao acessar:

```text
http://localhost:8088
```

voce ainda vera apenas a resposta de teste do proxy.

O roteamento abaixo sera implementado no Passo 7:

```text
http://localhost:8088/i/escola-a -> moodle_escola_a
http://localhost:8088/i/escola-b -> moodle_escola_b
```

Se quiser fazer um teste temporario agora, edite `proxy/Caddyfile.local` assim:

```caddyfile
:80 {
    redir /i/escola-a /i/escola-a/
    redir /i/escola-b /i/escola-b/

    handle_path /i/escola-a/* {
        reverse_proxy moodle_escola_a:80
    }

    handle_path /i/escola-b/* {
        reverse_proxy moodle_escola_b:80
    }

    respond "Proxy local da infraestrutura Moodle funcionando" 200
}
```

Depois recarregue o proxy:

```sh
docker exec moodle_proxy caddy reload --config /etc/caddy/Caddyfile
```

Entretanto, a configuracao oficial e a validacao completa do proxy ficam para o Passo 7.

## Etapa 20: Comandos uteis do dia a dia

Ver status dos containers das instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

Ver logs da escola A:

```sh
docker logs moodle_escola_a
```

Ver logs da escola B:

```sh
docker logs moodle_escola_b
```

Entrar em um shell dentro da escola A:

```sh
docker exec -it moodle_escola_a sh
```

Entrar em um shell dentro da escola B:

```sh
docker exec -it moodle_escola_b sh
```

Sair do shell:

```sh
exit
```

Ver uso de CPU e memoria:

```sh
docker stats
```

Ver apenas os containers Moodle:

```sh
docker stats moodle_escola_a moodle_escola_b
```

## Etapa 21: Parar os containers das instituicoes sem apagar dados

Para parar os containers:

```sh
docker compose -f docker-compose.instituicoes.yml stop
```

Para iniciar novamente:

```sh
docker compose -f docker-compose.instituicoes.yml start
```

Para remover os containers sem apagar volumes:

```sh
docker compose -f docker-compose.instituicoes.yml down
```

Depois de `down`, os volumes continuam existindo.

Confirme:

```sh
docker volume ls
```

Os volumes ainda devem aparecer:

```text
moodledata_escola_a
moodledata_escola_b
```

Para subir novamente:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

## Etapa 22: Quando apagar tudo do Passo 5

Use esta etapa apenas se quiser limpar os dados locais das instituicoes.

Primeiro, pare e remova os containers:

```sh
docker compose -f docker-compose.instituicoes.yml down
```

Depois remova os volumes das instituicoes:

```sh
docker volume rm moodledata_escola_a
```

```sh
docker volume rm moodledata_escola_b
```

Atencao: remover volumes apaga os arquivos do `moodledata` dessas instituicoes.

Essa limpeza nao apaga o banco MariaDB. Os bancos `moodle_escola_a` e `moodle_escola_b` continuam no volume `moodle_db_data`.

## Problemas comuns

### Erro: `network moodle_net declared as external, but could not be found`

Significa que a rede compartilhada ainda nao existe.

Resolva subindo a infraestrutura:

```sh
docker compose -f docker-compose.infra.yml up -d
```

Depois confira:

```sh
docker network ls
```

### Erro: `pull access denied for w3soft/moodle`

Significa que a imagem local ainda nao foi criada.

Construa a imagem:

```sh
docker compose build moodle
```

Depois tente subir as instituicoes novamente:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

### Erro: `Missing required environment variable`

Significa que o container nao recebeu alguma variavel obrigatoria.

Confira o arquivo `.env`:

```sh
sed -n '1,80p' secrets/escola-a.local.env
```

ou:

```sh
sed -n '1,80p' secrets/escola-b.local.env
```

Depois recrie o container:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

### Erro de acesso ao banco

Teste a conexao manualmente:

```sh
docker exec moodle_escola_a mariadb -h db -u moodle_escola_a -psenha-local-escola-a -e "SELECT 1;" moodle_escola_a
```

Se falhar, volte ao Passo 4 e confira:

- se o banco existe;
- se o usuario existe;
- se a senha esta igual ao arquivo `.env`;
- se o `GRANT` foi aplicado no banco correto.

### Container reiniciando sem parar

Veja os logs:

```sh
docker logs moodle_escola_a
```

ou:

```sh
docker logs moodle_escola_b
```

Procure por mensagens de erro de:

- variaveis ausentes;
- permissao em `/var/www/moodledata`;
- conexao com banco;
- erro de PHP;
- erro do Apache.

## Checklist final do Passo 5

Antes de considerar este passo concluido, confirme:

- `docker-compose.instituicoes.yml` foi criado;
- `docker compose -f docker-compose.instituicoes.yml config` nao mostra erro;
- `moodle_escola_a` esta rodando;
- `moodle_escola_b` esta rodando;
- os dois containers usam a imagem `w3soft/moodle:2026.07.1-local`;
- os dois containers estao na rede `moodle_net`;
- a escola A usa `MOODLE_DB_NAME=moodle_escola_a`;
- a escola B usa `MOODLE_DB_NAME=moodle_escola_b`;
- o usuario da escola A nao acessa o banco da escola B;
- `moodledata_escola_a` existe;
- `moodledata_escola_b` existe;
- os arquivos criados no `moodledata` da escola A nao aparecem na escola B;
- os arquivos criados no `moodledata` da escola B nao aparecem na escola A.

## Proximo passo

Depois deste passo, os containers Moodle por instituicao existem, mas ainda nao ha roteamento final pelo proxy.

O proximo passo sera configurar o Redis com prefixos exclusivos e, depois, configurar o proxy reverso para acessar:

```text
http://localhost:8088/i/escola-a
http://localhost:8088/i/escola-b
```

