# Passo 1: Padronizar a imagem Docker do Moodle

## Objetivo deste passo

Neste primeiro passo, o objetivo e transformar a imagem Docker do Moodle em um artefato padronizado, versionado e reutilizavel.

Hoje o projeto possui dois servicos que usam o mesmo codigo Moodle:

- `moodle`: container web principal;
- `cron`: container que executa o cron do Moodle.

No `docker-compose.yml` atual, os dois servicos fazem `build: ./moodle`. Isso funciona, mas ainda nao deixa explicito que ambos deveriam usar exatamente a mesma imagem Moodle.

Apos este passo, a ideia sera trabalhar com uma imagem nomeada e versionada, por exemplo:

```text
w3soft/moodle:2026.06.1-local
```

Essa imagem sera usada por todos os containers Moodle, inclusive futuramente por `moodle_escola_a`, `moodle_escola_b`, `moodle_escola_c` e assim por diante.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- verificar se Docker e Docker Compose estao instalados;
- entender a diferenca entre imagem e container;
- construir uma imagem com `docker build`;
- nomear uma imagem com tag;
- listar imagens locais;
- inspecionar uma imagem;
- usar a mesma imagem em mais de um servico no Compose;
- subir containers com `docker compose up`;
- verificar logs;
- parar e remover containers sem apagar volumes;
- entender como versionar uma imagem para atualizacoes futuras.

## Conceitos rapidos antes dos comandos

### Imagem

Uma imagem Docker e como um molde imutavel. Ela contem o sistema de arquivos e as instrucoes necessarias para iniciar containers.

Neste projeto, a imagem Moodle contem:

- PHP 8.3 com Apache;
- extensoes PHP necessarias;
- codigo do Moodle;
- arquivo `php.ini`;
- arquivo `config.php`.

### Container

Um container e uma execucao de uma imagem.

Voce pode criar varios containers a partir da mesma imagem. Isso e exatamente o que sera usado na arquitetura multi-instituicao.

Exemplo futuro:

```text
Imagem unica:
  w3soft/moodle:2026.06.1-local

Containers criados a partir dela:
  moodle_escola_a
  moodle_escola_b
  moodle_escola_c
```

### Tag

Uma tag e uma versao nomeada de uma imagem.

Exemplo:

```text
w3soft/moodle:2026.06.1-local
```

Neste nome:

- `w3soft/moodle` e o nome da imagem;
- `2026.06.1-local` e a tag;
- `local` indica que esta imagem foi criada para teste local.

## Decisao tecnica deste passo

Neste primeiro momento, vamos manter a imagem atual baseada em:

```dockerfile
FROM php:8.3-apache
```

Isso reduz a quantidade de mudancas e permite aprender Docker com uma alteracao controlada.

A migracao para `php:8.3-fpm` continua sendo recomendada para uma arquitetura mais madura com proxy reverso dedicado, mas ela deve entrar em um passo posterior. Primeiro vamos padronizar e versionar a imagem existente.

## Estrutura atual relevante

Arquivos envolvidos neste passo:

```text
docker-compose.yml
moodle/Dockerfile
moodle/php.ini
moodle/config.php
```

O `Dockerfile` atual fica em:

```text
moodle/Dockerfile
```

Ele e responsavel por:

1. partir da imagem `php:8.3-apache`;
2. instalar dependencias do sistema;
3. instalar extensoes PHP;
4. baixar o Moodle;
5. copiar `php.ini`;
6. copiar `config.php`;
7. definir `/var/www/html` como diretorio de trabalho.

## Etapa 1: Confirmar que voce esta na pasta do projeto

Execute:

```sh
pwd
```

Voce deve estar na pasta:

```text
/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker
```

Se nao estiver, entre nela:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

Confirme os arquivos principais:

```sh
ls
```

Resultado esperado:

```text
docker-compose.yml
moodle
docs
```

Veja tambem o conteudo da pasta `moodle`:

```sh
ls moodle
```

Resultado esperado, no minimo:

```text
Dockerfile
config.php
php.ini
```

## Etapa 2: Verificar se Docker esta instalado

Execute:

```sh
docker --version
```

Exemplo de resultado esperado:

```text
Docker version 27.x.x
```

Agora verifique o Docker Compose:

```sh
docker compose version
```

Exemplo de resultado esperado:

```text
Docker Compose version v2.x.x
```

Se algum desses comandos falhar, abra o Docker Desktop e tente novamente depois de alguns segundos.

## Etapa 3: Verificar se o Docker esta respondendo

Execute:

```sh
docker info
```

Esse comando mostra informacoes do Docker Engine.

Se aparecer um erro parecido com:

```text
Cannot connect to the Docker daemon
```

significa que o Docker Desktop provavelmente nao esta aberto ou ainda esta inicializando.

## Etapa 4: Ver o Compose atual

Execute:

```sh
docker compose config
```

Esse comando valida e imprime a configuracao final do Compose.

Ele e util para detectar erro de sintaxe antes de subir containers.

Neste projeto, voce deve ver servicos como:

```text
db
moodle
cron
```

## Etapa 5: Entender o problema atual

Abra o `docker-compose.yml`:

```sh
sed -n '1,220p' docker-compose.yml
```

Observe que o servico `moodle` possui:

```yaml
build: ./moodle
```

E o servico `cron` tambem possui:

```yaml
build: ./moodle
```

Isso significa que os dois servicos dependem do mesmo contexto de build, mas o Compose ainda nao deixa a imagem padronizada de forma clara.

O que queremos e que a imagem tenha nome e versao.

## Etapa 6: Criar um backup do Compose antes de editar

Execute:

```sh
cp docker-compose.yml docker-compose.yml.bak-passo-01
```

Confira se o backup foi criado:

```sh
ls docker-compose.yml.bak-passo-01
```

Esse backup permite comparar ou voltar manualmente caso voce queira revisar a mudanca.

## Etapa 7: Editar o Compose para nomear a imagem Moodle

Abra o arquivo:

```sh
code docker-compose.yml
```

Se voce nao usa VS Code pelo terminal, abra o arquivo manualmente no editor de sua preferencia.

No servico `moodle`, altere de:

```yaml
  moodle:
    build: ./moodle
    container_name: moodle_app
```

Para:

```yaml
  moodle:
    image: w3soft/moodle:2026.06.1-local
    build:
      context: ./moodle
    container_name: moodle_app
```

Agora, no servico `cron`, altere de:

```yaml
  cron:
    build: ./moodle
    container_name: moodle_cron
```

Para:

```yaml
  cron:
    image: w3soft/moodle:2026.06.1-local
    container_name: moodle_cron
```

O resultado importante e:

- somente o servico `moodle` constroi a imagem;
- o servico `cron` reutiliza a imagem ja criada;
- ambos passam a usar `w3soft/moodle:2026.06.1-local`.

## Etapa 8: Conferir o trecho final esperado do Compose

Depois da edicao, o trecho dos servicos `moodle` e `cron` deve ficar parecido com:

```yaml
  moodle:
    image: w3soft/moodle:2026.06.1-local
    build:
      context: ./moodle
    container_name: moodle_app
    restart: unless-stopped
    ports:
      - "8080:80"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - moodledata:/var/www/moodledata
    networks:
      - moodle_net

  cron:
    image: w3soft/moodle:2026.06.1-local
    container_name: moodle_cron
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - moodledata:/var/www/moodledata
    command: >
      sh -c "while true; do php /var/www/html/admin/cli/cron.php; sleep 60; done"
    networks:
      - moodle_net
```

## Etapa 9: Validar a sintaxe do Compose apos a edicao

Execute:

```sh
docker compose config
```

Se o arquivo estiver correto, o Compose imprimira a configuracao final.

Se houver erro de identacao, o Compose mostrara uma mensagem. Em YAML, espacos importam bastante. Use sempre espacos, nao tabs.

## Etapa 10: Construir a imagem Moodle padronizada

Execute:

```sh
docker compose build moodle
```

O que esse comando faz:

- le o servico `moodle` no `docker-compose.yml`;
- encontra o `build.context: ./moodle`;
- executa o `moodle/Dockerfile`;
- cria a imagem local;
- aplica a tag `w3soft/moodle:2026.06.1-local`.

Se for a primeira execucao, pode demorar porque o Docker precisa baixar imagens base e pacotes.

## Etapa 11: Verificar se a imagem foi criada

Execute:

```sh
docker image ls w3soft/moodle
```

Resultado esperado:

```text
REPOSITORY      TAG                IMAGE ID       CREATED          SIZE
w3soft/moodle   2026.06.1-local    ...            ...              ...
```

Se a imagem aparecer nessa lista, o build funcionou.

## Etapa 12: Inspecionar a imagem criada

Execute:

```sh
docker image inspect w3soft/moodle:2026.06.1-local
```

Esse comando mostra muitos detalhes em JSON, como:

- ID da imagem;
- arquitetura;
- sistema operacional;
- variaveis de ambiente;
- comando padrao;
- camadas internas;
- data de criacao.

Para aprender, voce pode buscar principalmente por:

```text
"Architecture"
"Os"
"Config"
"WorkingDir"
```

## Etapa 13: Ver o historico de camadas da imagem

Execute:

```sh
docker history w3soft/moodle:2026.06.1-local
```

Esse comando mostra as camadas da imagem.

Voce deve ver camadas relacionadas a:

- imagem base `php:8.3-apache`;
- instalacao de pacotes;
- instalacao de extensoes PHP;
- clone do Moodle;
- copia de `php.ini`;
- copia de `config.php`.

Esse comando ajuda a entender que uma imagem Docker e formada por camadas reutilizaveis.

## Etapa 14: Subir o banco de dados

Antes de subir o Moodle, suba o banco:

```sh
docker compose up -d db
```

O `-d` significa detached mode, ou seja, o container fica rodando em segundo plano.

Verifique se o container subiu:

```sh
docker compose ps
```

Voce deve ver o servico `db` como iniciado.

## Etapa 15: Acompanhar a saude do banco

O `docker-compose.yml` possui um `healthcheck` no banco.

Execute:

```sh
docker compose ps db
```

Espere ate aparecer algo como:

```text
healthy
```

Tambem e possivel acompanhar os logs:

```sh
docker compose logs -f db
```

Para sair dos logs, pressione:

```text
Ctrl + C
```

## Etapa 16: Subir o Moodle usando a imagem padronizada

Execute:

```sh
docker compose up -d moodle
```

Verifique os containers:

```sh
docker compose ps
```

Resultado esperado:

```text
db       running / healthy
moodle   running
```

Agora veja os logs do Moodle:

```sh
docker compose logs -f moodle
```

Para sair:

```text
Ctrl + C
```

## Etapa 17: Abrir o Moodle no navegador

Acesse:

```text
http://localhost:8080
```

Se tudo estiver correto, o Moodle deve responder.

Se for a primeira execucao com volumes novos, ele pode iniciar o processo de instalacao/configuracao.

## Etapa 18: Subir o cron usando a mesma imagem

Agora suba o cron:

```sh
docker compose up -d cron
```

Verifique:

```sh
docker compose ps
```

Agora voce deve ver:

```text
db
moodle
cron
```

Veja os logs do cron:

```sh
docker compose logs -f cron
```

Para sair:

```text
Ctrl + C
```

Neste momento, o ponto principal e que `moodle` e `cron` estao usando a mesma imagem:

```text
w3soft/moodle:2026.06.1-local
```

## Etapa 19: Confirmar qual imagem cada container usa

Execute:

```sh
docker inspect moodle_app --format '{{.Config.Image}}'
```

Resultado esperado:

```text
w3soft/moodle:2026.06.1-local
```

Agora confirme o cron:

```sh
docker inspect moodle_cron --format '{{.Config.Image}}'
```

Resultado esperado:

```text
w3soft/moodle:2026.06.1-local
```

Se os dois containers mostram a mesma imagem, este passo foi implementado corretamente.

## Etapa 20: Confirmar que os containers sao diferentes, mas a imagem e a mesma

Liste os containers:

```sh
docker ps
```

Voce deve ver containers diferentes:

```text
moodle_app
moodle_cron
```

Agora liste as imagens:

```sh
docker image ls w3soft/moodle
```

Voce deve ver uma unica imagem Moodle padronizada:

```text
w3soft/moodle   2026.06.1-local
```

Essa e uma das ideias mais importantes deste projeto:

```text
1 imagem Moodle
varios containers Moodle
```

## Etapa 21: Testar um segundo container temporario com a mesma imagem

Este teste ajuda a entender que voce pode criar outro container a partir da mesma imagem.

Execute:

```sh
docker run --rm w3soft/moodle:2026.06.1-local php -v
```

O que esse comando faz:

- cria um container temporario;
- usa a imagem `w3soft/moodle:2026.06.1-local`;
- executa `php -v`;
- remove o container ao terminar por causa do `--rm`.

Resultado esperado:

```text
PHP 8.3.x
```

Agora confira os modulos PHP instalados:

```sh
docker run --rm w3soft/moodle:2026.06.1-local php -m
```

Voce deve ver extensoes como:

```text
curl
exif
gd
intl
mysqli
opcache
pdo_mysql
soap
zip
```

## Etapa 22: Testar se o codigo do Moodle esta dentro da imagem

Execute:

```sh
docker run --rm w3soft/moodle:2026.06.1-local php /var/www/html/admin/cli/checks.php
```

Esse comando executa um script CLI do Moodle dentro de um container temporario.

Dependendo do estado da configuracao e do banco, podem aparecer avisos. Neste passo, o objetivo principal e confirmar que o caminho existe e que a imagem contem o Moodle.

Voce tambem pode listar o diretorio:

```sh
docker run --rm w3soft/moodle:2026.06.1-local ls /var/www/html
```

Resultado esperado: varios arquivos e diretorios do Moodle, como:

```text
admin
course
lib
mod
theme
version.php
```

## Etapa 23: Parar os containers sem apagar dados

Quando terminar o teste, voce pode parar os containers:

```sh
docker compose down
```

Esse comando:

- para os containers;
- remove os containers;
- preserva os volumes.

Os dados do banco e do `moodledata` continuam guardados nos volumes Docker.

## Etapa 24: Subir tudo novamente

Execute:

```sh
docker compose up -d
```

Como a imagem ja foi construida, o Docker tende a reaproveitar o que ja existe.

Verifique:

```sh
docker compose ps
```

Depois acesse novamente:

```text
http://localhost:8080
```

## Etapa 25: Quando reconstruir a imagem

Voce precisa reconstruir a imagem quando mudar arquivos que entram no build, por exemplo:

- `moodle/Dockerfile`;
- `moodle/php.ini`;
- `moodle/config.php`;
- plugins copiados para dentro da imagem no futuro;
- versao do Moodle no `git clone`.

Para reconstruir:

```sh
docker compose build moodle
```

Depois recrie os containers que usam a imagem:

```sh
docker compose up -d --force-recreate moodle cron
```

## Etapa 26: Criar uma nova versao da imagem

Quando houver uma mudanca relevante, nao substitua silenciosamente a mesma tag.

Por exemplo, a versao atual:

```text
w3soft/moodle:2026.06.1-local
```

Uma proxima versao poderia ser:

```text
w3soft/moodle:2026.06.2-local
```

Para isso, altere o `docker-compose.yml`:

```yaml
image: w3soft/moodle:2026.06.2-local
```

Depois construa:

```sh
docker compose build moodle
```

Liste as imagens:

```sh
docker image ls w3soft/moodle
```

Voce deve ver as duas:

```text
w3soft/moodle   2026.06.2-local
w3soft/moodle   2026.06.1-local
```

Isso ajuda a testar uma versao nova sem perder a referencia da anterior.

## Etapa 27: Como voltar para a versao anterior

Se voce criou uma nova tag e quer voltar para a anterior, edite o Compose e retorne:

```yaml
image: w3soft/moodle:2026.06.1-local
```

Depois recrie os containers:

```sh
docker compose up -d --force-recreate moodle cron
```

Importante: voltar a imagem nao desfaz mudancas no banco de dados nem no `moodledata`. Para rollback real de producao, tambem e necessario restaurar backup do banco e dos arquivos.

## Etapa 28: Limpar containers parados, se necessario

Para ver containers parados:

```sh
docker ps -a
```

Para remover apenas containers parados:

```sh
docker container prune
```

O Docker pedira confirmacao.

Atencao: esse comando remove containers parados, mas nao deve remover volumes.

## Etapa 29: Nao apagar volumes sem querer

Evite usar este comando durante o aprendizado:

```sh
docker compose down -v
```

O `-v` remove volumes.

Neste projeto, isso pode apagar:

- dados do MariaDB;
- arquivos do `moodledata`.

Para parar o ambiente preservando dados, use:

```sh
docker compose down
```

## Etapa 30: Comandos de verificacao final

Use estes comandos para validar o Passo 1:

```sh
docker compose config
```

```sh
docker image ls w3soft/moodle
```

```sh
docker compose up -d
```

```sh
docker compose ps
```

```sh
docker inspect moodle_app --format '{{.Config.Image}}'
```

```sh
docker inspect moodle_cron --format '{{.Config.Image}}'
```

Resultados esperados:

```text
moodle_app  -> w3soft/moodle:2026.06.1-local
moodle_cron -> w3soft/moodle:2026.06.1-local
```

## Resultado esperado do Passo 1

Ao final deste passo:

- existe uma imagem Moodle local nomeada e versionada;
- `moodle` e `cron` usam a mesma imagem;
- o Compose deixa explicito qual imagem esta em uso;
- voce consegue reconstruir a imagem quando necessario;
- voce consegue criar novas tags para novas versoes;
- voce entende que varios containers podem nascer da mesma imagem.

## Por que isso prepara o projeto para varias instituicoes

A arquitetura recomendada para varias instituicoes depende desta ideia:

```text
Uma unica imagem Moodle padronizada
Varios containers Moodle independentes
```

No futuro, em vez de:

```text
moodle_app
moodle_cron
```

voce podera ter:

```text
moodle_escola_a
moodle_escola_b
moodle_escola_c
```

Todos usando a mesma imagem:

```text
w3soft/moodle:2026.06.1-local
```

O que muda por instituicao nao deve ser o codigo da imagem. O que muda por instituicao deve ser:

- variaveis de ambiente;
- banco de dados;
- usuario e senha;
- volume `moodledata`;
- subdominio;
- prefixo Redis;
- limites de CPU e memoria.

Essa separacao e a base para economizar recursos e manter organizacao operacional.

## Checklist final

Marque cada item quando concluir:

- [ ] Entrei na pasta correta do projeto.
- [ ] Confirmei `docker --version`.
- [ ] Confirmei `docker compose version`.
- [ ] Rodei `docker compose config`.
- [ ] Fiz backup do `docker-compose.yml`.
- [ ] Adicionei `image: w3soft/moodle:2026.06.1-local` no servico `moodle`.
- [ ] Mantive `build.context: ./moodle` no servico `moodle`.
- [ ] Troquei o servico `cron` para usar a mesma imagem.
- [ ] Rodei `docker compose build moodle`.
- [ ] Confirmei a imagem com `docker image ls w3soft/moodle`.
- [ ] Subi `db`, `moodle` e `cron`.
- [ ] Confirmei que `moodle_app` usa `w3soft/moodle:2026.06.1-local`.
- [ ] Confirmei que `moodle_cron` usa `w3soft/moodle:2026.06.1-local`.
- [ ] Acessei `http://localhost:8080`.

## Proximo passo

Depois que este passo estiver funcionando localmente, o proximo documento deve implementar o Passo 2:

```text
Transformar moodle/config.php em configuracao por variaveis de ambiente.
```

Esse sera o passo que realmente prepara o mesmo container para funcionar como `escola_a`, `escola_b`, `escola_c` etc., mudando apenas as configuracoes externas.

