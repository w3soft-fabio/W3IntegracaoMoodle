# Passo 6: Configurar Redis com prefixos exclusivos

## Objetivo deste passo

Neste passo, o objetivo e fazer cada instituicao Moodle usar o Redis compartilhado sem misturar sessoes ou caches.

A regra principal e:

```text
Um Redis compartilhado
Varios Moodles
Um prefixo Redis exclusivo por instituicao
```

Exemplo:

```text
moodle_escola_a -> Redis -> chaves iniciando com escola_a_
moodle_escola_b -> Redis -> chaves iniciando com escola_b_
```

Isso permite economizar recursos, porque voce roda apenas um container Redis, mas ainda reduz o risco de colisao entre dados de instituicoes diferentes.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- entender o papel do Redis no Moodle;
- verificar se um container Redis esta saudavel;
- testar conectividade entre containers Docker;
- instalar uma extensao PHP dentro da imagem Docker;
- rebuildar uma imagem Docker;
- configurar variaveis de ambiente por instituicao;
- configurar o Moodle para usar Redis como storage de sessoes;
- usar prefixos diferentes para cada instituicao;
- inspecionar chaves dentro do Redis com `redis-cli`;
- validar isolamento entre instituicoes;
- limpar somente chaves de teste no Redis.

## Resultado esperado

Ao final deste passo:

- o container `moodle_redis` estara rodando;
- a imagem `w3soft/moodle:2026.06.1-local` tera a extensao PHP `redis`;
- a imagem Moodle usara `moodle/docker-entrypoint.sh` como entrypoint;
- o entrypoint configurara o Apache para servir o Moodle em subcaminhos como `/i/escola-a`;
- o Caddy encaminhara `/i/escola-a/` para `moodle_escola_a` e `/i/escola-b/` para `moodle_escola_b`;
- `moodle_escola_a` usara prefixo `escola_a_`;
- `moodle_escola_b` usara prefixo `escola_b_`;
- cada Moodle gravara sessoes no Redis com prefixos separados;
- voce conseguira validar os prefixos usando `redis-cli`.

## Conceitos rapidos antes dos comandos

### O que e Redis

Redis e um banco de dados em memoria usado normalmente para dados temporarios e de acesso rapido.

No Moodle, ele pode ser usado principalmente para:

- sessoes de usuarios;
- cache de aplicacao;
- alguns cenarios de cache distribuido.

Neste passo, a configuracao principal sera para sessoes. Essa parte e confiavel para configurar via `config.php`.

### Por que usar prefixo

O Redis guarda dados em chaves.

Sem prefixo, dois Moodles diferentes poderiam gerar chaves com nomes iguais ou dificeis de separar.

Com prefixo:

```text
escola_a_session_xxxxx
escola_b_session_xxxxx
```

fica claro que cada chave pertence a uma instituicao.

### Redis compartilhado nao significa Moodle compartilhado

Mesmo usando o mesmo Redis:

- cada instituicao continua tendo seu proprio container Moodle;
- cada instituicao continua tendo seu proprio banco;
- cada instituicao continua tendo seu proprio `moodledata`;
- cada instituicao usa apenas um namespace diferente dentro do Redis.

### Redis no Docker

Dentro da rede Docker `moodle_net`, os containers nao precisam acessar o Redis por `localhost`.

Eles acessam pelo nome do servico:

```text
redis
```

Este nome vem do servico `redis` definido em `docker-compose.infra.yml`.

## Pre-requisitos

Antes de iniciar este passo, conclua:

```text
docs/passo-01-padronizar-imagem-moodle.md
docs/passo-02-configuracao-por-variaveis.md
docs/passo-03-infraestrutura-compartilhada.md
docs/passo-04-criar-bancos-e-usuarios.md
docs/passo-05-criar-servico-moodle-por-instituicao.md
```

Arquivos esperados no projeto:

```text
docker-compose.infra.yml
docker-compose.instituicoes.yml
moodle/Dockerfile
moodle/config.php
moodle/docker-entrypoint.sh
proxy/Caddyfile.local
secrets/escola-a.local.env
secrets/escola-b.local.env
```

Containers esperados depois dos passos anteriores:

```text
moodle_db
moodle_redis
moodle_proxy
moodle_escola_a
moodle_escola_b
```

## Decisao tecnica deste passo

Neste laboratorio local vamos configurar:

```text
Redis host: redis
Redis porta: 6379
Redis database: 0
Prefixo escola A: escola_a_
Prefixo escola B: escola_b_
```

Para sessoes, o Moodle usara:

```text
escola_a_session_
escola_b_session_
```

Para cache de aplicacao, quando voce configurar pelo painel administrativo do Moodle, use:

```text
escola_a_cache_
escola_b_cache_
```

Para acesso via proxy local, o commit `334f846da94f93ec61f6e9fab3e8a80430cbbb0a` tambem padroniza:

```text
Escola A: http://localhost:8088/i/escola-a/
Escola B: http://localhost:8088/i/escola-b/
```

O Moodle recebe o path publico pela variavel `MOODLE_URL`. O entrypoint da imagem extrai esse path e gera um `Alias` no Apache para que o Moodle funcione atras do Caddy usando esses subcaminhos.

## Referencias oficiais usadas

- Moodle Docs: Redis cache store: <https://docs.moodle.org/405/en/Redis_cache_store>
- Moodle Docs: Session handling: <https://docs.moodle.org/405/en/Session_handling>
- Docker Docs: docker compose up: <https://docs.docker.com/reference/cli/docker/compose/up/>
- Docker Docs: docker exec: <https://docs.docker.com/reference/cli/docker/container/exec/>

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

## Etapa 2: Verificar se o Redis existe no Compose de infraestrutura

Execute:

```sh
sed -n '1,220p' docker-compose.infra.yml
```

Procure por este servico:

```yaml
redis:
  image: redis:7-alpine
  container_name: moodle_redis
```

Se o servico ja existir, nao altere nada nesta etapa.

Se ele nao existir, adicione este bloco dentro de `services`:

```yaml
  redis:
    image: redis:7-alpine
    container_name: moodle_redis
    restart: unless-stopped
    command:
      - redis-server
      - --appendonly
      - "yes"
    volumes:
      - moodle_redis_data:/data
    networks:
      - moodle_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
```

Tambem confirme que existe o volume:

```yaml
volumes:
  moodle_redis_data:
    name: moodle_redis_data
```

## Etapa 3: Subir a infraestrutura compartilhada

Execute:

```sh
docker compose -f docker-compose.infra.yml up -d
```

O que este comando faz:

- le o arquivo `docker-compose.infra.yml`;
- cria a rede `moodle_net`, se ela ainda nao existir;
- cria os volumes de infraestrutura, se ainda nao existirem;
- sobe `moodle_db`, `moodle_redis` e `moodle_proxy` em segundo plano.

Verifique os containers:

```sh
docker compose -f docker-compose.infra.yml ps
```

Resultado esperado:

```text
moodle_db       running
moodle_redis    running
moodle_proxy    running
```

O texto exato pode variar, mas os tres containers devem estar em execucao.

## Etapa 4: Testar se o Redis responde

Execute:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

Esse comando significa:

```text
docker exec       -> execute um comando dentro de um container
moodle_redis      -> nome do container
redis-cli ping    -> comando enviado ao Redis
```

Se nao retornar `PONG`, veja os logs:

```sh
docker logs moodle_redis --tail 80
```

## Etapa 5: Verificar se o Redis esta na rede Docker correta

Execute:

```sh
docker network inspect moodle_net
```

Procure por:

```text
moodle_redis
moodle_db
moodle_proxy
```

Depois que os containers Moodle estiverem rodando, essa mesma rede tambem devera mostrar:

```text
moodle_escola_a
moodle_escola_b
```

## Etapa 6: Verificar as variaveis Redis de cada instituicao

Primeiro confirme a URL publica de cada instituicao, porque o entrypoint usa o path de `MOODLE_URL` para configurar o Apache:

```sh
grep '^MOODLE_URL' secrets/escola-a.local.env
```

Resultado esperado para escola A:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
```

```sh
grep '^MOODLE_URL' secrets/escola-b.local.env
```

Resultado esperado para escola B:

```env
MOODLE_URL=http://localhost:8088/i/escola-b
```

Se preferir informar o path diretamente, voce pode usar `MOODLE_PUBLIC_PATH`, mas neste laboratorio ele nao e necessario porque o entrypoint consegue extrair `/i/escola-a` e `/i/escola-b` de `MOODLE_URL`.

Execute:

```sh
grep '^MOODLE_REDIS' secrets/escola-a.local.env
```

Resultado esperado para escola A:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

Execute:

```sh
grep '^MOODLE_REDIS' secrets/escola-b.local.env
```

Resultado esperado para escola B:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_b_
```

Pontos importantes:

- `MOODLE_REDIS_HOST` deve ser `redis`, nao `localhost`;
- `MOODLE_REDIS_PORT` deve ser `6379`;
- `MOODLE_REDIS_PREFIX` deve ser diferente para cada instituicao;
- use apenas letras, numeros e `_` no prefixo.

Se precisar editar:

```sh
nano secrets/escola-a.local.env
```

```sh
nano secrets/escola-b.local.env
```

## Etapa 7: Verificar se a imagem PHP tem extensao Redis

Suba os containers Moodle, caso ainda nao estejam rodando:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

Verifique a extensao PHP no container da escola A:

```sh
docker exec moodle_escola_a php -m | grep -i '^redis$'
```

Resultado esperado:

```text
redis
```

Verifique tambem na escola B:

```sh
docker exec moodle_escola_b php -m | grep -i '^redis$'
```

Resultado esperado:

```text
redis
```

Se o comando nao retornar nada, a imagem Moodle ainda nao tem a extensao PHP `redis`.

Nesse caso, siga a etapa 8.

## Etapa 8: Instalar a extensao PHP Redis na imagem Moodle

Abra o `Dockerfile`:

```sh
nano moodle/Dockerfile
```

Localize este trecho:

```dockerfile
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        soap \
        exif \
        opcache \
        mbstring \
        curl \
    && a2enmod rewrite headers expires \
    && rm -rf /var/lib/apt/lists/*
```

Altere para incluir:

```dockerfile
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        soap \
        exif \
        opcache \
        mbstring \
        curl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && a2enmod rewrite headers expires \
    && rm -rf /var/lib/apt/lists/*
```

Salve o arquivo.

Ainda no `Dockerfile`, confirme que o entrypoint do Moodle e copiado para dentro da imagem:

```dockerfile
COPY php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY config.php /var/www/html/config.php
COPY docker-entrypoint.sh /usr/local/bin/moodle-entrypoint
```

Confirme tambem que ele recebe permissao de execucao:

```dockerfile
RUN chown www-data:www-data /var/www/html/config.php \
    && chmod +x /usr/local/bin/moodle-entrypoint
```

E que o final do arquivo define o entrypoint e o comando padrao:

```dockerfile
WORKDIR /var/www/html

ENTRYPOINT ["moodle-entrypoint"]
CMD ["apache2-foreground"]
```

Esse entrypoint e importante para este passo porque ele prepara o Apache para servir o Moodle no subcaminho definido em `MOODLE_URL`, como `/i/escola-a` ou `/i/escola-b`.

Confirme que o arquivo existe:

```sh
sed -n '1,180p' moodle/docker-entrypoint.sh
```

O script deve:

- ler `MOODLE_PUBLIC_PATH`, se ela existir;
- se `MOODLE_PUBLIC_PATH` nao existir, extrair o path de `MOODLE_URL`;
- validar o path publico;
- criar `/etc/apache2/conf-enabled/moodle-public-path.conf` com os `Alias` do Apache;
- chamar `docker-php-entrypoint "$@"` no final.

Recrie a imagem local:

```sh
docker compose -f docker-compose.yml build moodle
```

O que este comando faz:

- le o servico `moodle` do `docker-compose.yml`;
- executa novamente o `moodle/Dockerfile`;
- instala a extensao `redis`;
- copia `moodle/docker-entrypoint.sh` para `/usr/local/bin/moodle-entrypoint`;
- define `moodle-entrypoint` como entrypoint da imagem;
- recria a imagem `w3soft/moodle:2026.06.1-local`.

Se voce estiver usando apenas `docker-compose.instituicoes.yml`, confira se a imagem esperada existe:

```sh
docker image ls w3soft/moodle
```

Depois recrie os containers das instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

Teste novamente:

```sh
docker exec moodle_escola_a php -m | grep -i '^redis$'
```

```sh
docker exec moodle_escola_b php -m | grep -i '^redis$'
```

Resultado esperado:

```text
redis
```

## Etapa 9: Configurar sessoes Redis no `config.php`

Abra o arquivo:

```sh
nano moodle/config.php
```

Localize esta linha no final do arquivo:

```php
$CFG->directorypermissions = 0777;
```

Antes dela, adicione este bloco:

```php
$redisHost = moodle_env_optional('MOODLE_REDIS_HOST', '');

if ($redisHost !== '') {
    $redisPrefix = moodle_env_required('MOODLE_REDIS_PREFIX');

    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = $redisHost;
    $CFG->session_redis_port = (int) moodle_env_optional('MOODLE_REDIS_PORT', '6379');
    $CFG->session_redis_database = (int) moodle_env_optional('MOODLE_REDIS_DATABASE', '0');
    $CFG->session_redis_prefix = $redisPrefix . 'session_';
    $CFG->session_redis_acquire_lock_timeout = 120;
    $CFG->session_redis_acquire_lock_retry = 100;
    $CFG->session_redis_lock_expire = 7200;

    $redisPassword = getenv('MOODLE_REDIS_PASSWORD');

    if ($redisPassword !== false && $redisPassword !== '') {
        $CFG->session_redis_auth = $redisPassword;
    }
}
```

O final do arquivo deve ficar nesta ordem:

```php
$redisHost = moodle_env_optional('MOODLE_REDIS_HOST', '');

if ($redisHost !== '') {
    $redisPrefix = moodle_env_required('MOODLE_REDIS_PREFIX');

    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = $redisHost;
    $CFG->session_redis_port = (int) moodle_env_optional('MOODLE_REDIS_PORT', '6379');
    $CFG->session_redis_database = (int) moodle_env_optional('MOODLE_REDIS_DATABASE', '0');
    $CFG->session_redis_prefix = $redisPrefix . 'session_';
    $CFG->session_redis_acquire_lock_timeout = 120;
    $CFG->session_redis_acquire_lock_retry = 100;
    $CFG->session_redis_lock_expire = 7200;

    $redisPassword = getenv('MOODLE_REDIS_PASSWORD');

    if ($redisPassword !== false && $redisPassword !== '') {
        $CFG->session_redis_auth = $redisPassword;
    }
}

$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');
```

Salve o arquivo.

## Etapa 10: Rebuildar a imagem depois de alterar `config.php`

Como o `config.php` e copiado para dentro da imagem no `Dockerfile`, e necessario rebuildar a imagem.

Execute:

```sh
docker compose -f docker-compose.yml build moodle
```

Recrie os containers das instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

Verifique se os containers estao rodando:

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

Resultado esperado:

```text
moodle_escola_a    running
moodle_escola_b    running
```

## Etapa 11: Confirmar variaveis dentro dos containers

Verifique a escola A:

```sh
docker exec moodle_escola_a printenv | grep '^MOODLE_REDIS'
```

Resultado esperado:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

Verifique a escola B:

```sh
docker exec moodle_escola_b printenv | grep '^MOODLE_REDIS'
```

Resultado esperado:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_b_
```

Se as variaveis nao aparecerem, revise o `env_file` em `docker-compose.instituicoes.yml`.

## Etapa 12: Testar conectividade do Moodle ate o Redis

Teste a partir do container Moodle da escola A:

```sh
docker exec moodle_escola_a php -r '$r = new Redis(); $r->connect("redis", 6379); echo $r->ping(), PHP_EOL;'
```

Resultado esperado:

```text
1
```

ou:

```text
PONG
```

O retorno depende da versao da extensao PHP Redis.

Teste a escola B:

```sh
docker exec moodle_escola_b php -r '$r = new Redis(); $r->connect("redis", 6379); echo $r->ping(), PHP_EOL;'
```

Resultado esperado:

```text
1
```

ou:

```text
PONG
```

Se falhar, verifique:

```sh
docker logs moodle_redis --tail 80
```

```sh
docker logs moodle_escola_a --tail 80
```

```sh
docker logs moodle_escola_b --tail 80
```

## Etapa 13: Testar prefixos manualmente no Redis

Antes de depender do Moodle, faca um teste simples criando chaves com prefixos diferentes.

Crie uma chave para a escola A:

```sh
docker exec moodle_redis redis-cli SET escola_a_teste "ok escola a"
```

Resultado esperado:

```text
OK
```

Crie uma chave para a escola B:

```sh
docker exec moodle_redis redis-cli SET escola_b_teste "ok escola b"
```

Resultado esperado:

```text
OK
```

Liste as chaves da escola A:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_a_*'
```

Resultado esperado:

```text
escola_a_teste
```

Liste as chaves da escola B:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_b_*'
```

Resultado esperado:

```text
escola_b_teste
```

Consulte os valores:

```sh
docker exec moodle_redis redis-cli GET escola_a_teste
```

```sh
docker exec moodle_redis redis-cli GET escola_b_teste
```

Resultado esperado:

```text
ok escola a
ok escola b
```

Remova as chaves de teste:

```sh
docker exec moodle_redis redis-cli DEL escola_a_teste escola_b_teste
```

Resultado esperado:

```text
2
```

## Etapa 14: Acessar os Moodles e gerar sessoes reais

Antes de abrir o navegador, confirme que o proxy local tem as rotas das instituicoes:

```sh
sed -n '1,120p' proxy/Caddyfile.local
```

O arquivo deve conter:

```caddyfile
:80 {
    redir /i/escola-a /i/escola-a/
    redir /i/escola-b /i/escola-b/

    handle /i/escola-a/* {
        reverse_proxy moodle_escola_a:80
    }

    handle /i/escola-b/* {
        reverse_proxy moodle_escola_b:80
    }

    respond "Proxy local da infraestrutura Moodle funcionando" 200
}
```

Essas rotas fazem o Caddy enviar cada subcaminho para o container Moodle correto. Os `redir` garantem que a URL sem barra final tambem funcione.

Se voce alterar o `Caddyfile`, recarregue o proxy:

```sh
docker compose -f docker-compose.infra.yml up -d --force-recreate proxy
```

Acesse no navegador:

```text
http://localhost:8088/i/escola-a/
```

Depois acesse:

```text
http://localhost:8088/i/escola-b/
```

Faca login ou avance ate a tela de instalacao inicial, dependendo do estado do seu ambiente.

Em seguida, liste chaves de sessao da escola A:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_a_session_*' | head
```

Liste chaves de sessao da escola B:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_b_session_*' | head
```

Resultado esperado:

```text
chaves com escola_a_session_
chaves com escola_b_session_
```

Observacao: se nenhuma sessao aparecer, gere atividade no Moodle, faca login novamente e rode os comandos outra vez.

## Etapa 15: Verificar logs do Moodle

Verifique a escola A:

```sh
docker logs moodle_escola_a --tail 120
```

Verifique a escola B:

```sh
docker logs moodle_escola_b --tail 120
```

Nao devem aparecer erros como:

```text
Class "Redis" not found
Redis server went away
Connection refused
Missing required environment variable: MOODLE_REDIS_PREFIX
```

Se aparecer `Class "Redis" not found`, a extensao PHP Redis nao foi instalada ou a imagem antiga ainda esta em uso.

Se aparecer `Connection refused`, o Moodle nao conseguiu conectar no container Redis.

Se aparecer `Missing required environment variable`, revise os arquivos em `secrets/`.

## Etapa 16: Configurar cache de aplicacao Redis pelo painel do Moodle

A configuracao de sessoes ja foi feita em `config.php`.

Para cache de aplicacao, use o painel administrativo do Moodle em cada instituicao. O Moodle documenta essa configuracao pela interface administrativa.

Para a escola A:

1. Acesse `http://localhost:8088/i/escola-a/`.
2. Entre como administrador.
3. Va em `Site administration`.
4. Va em `Plugins`.
5. Va em `Caching`.
6. Va em `Configuration`.
7. Em `Installed cache stores`, encontre `Redis`.
8. Clique em `Add instance`.
9. Configure:

```text
Store name: redis_app
Server: redis:6379
Prefix: escola_a_cache_
```

10. Salve.
11. Em `Stores used when no mapping is present`, configure Redis para caches de aplicacao quando aplicavel.

Para a escola B, repita usando:

```text
Store name: redis_app
Server: redis:6379
Prefix: escola_b_cache_
```

Importante:

- nao use o mesmo prefixo de cache para duas instituicoes;
- nao use o mesmo prefixo para cache e sessao;
- nao configure cache Redis antes de confirmar que a extensao PHP Redis esta instalada;
- se a interface nao mostrar Redis, volte para a etapa 8.

## Etapa 17: Validar prefixos de cache

Depois de configurar o cache pelo painel e navegar por algumas paginas do Moodle, rode:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_a_cache_*' | head
```

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_b_cache_*' | head
```

Resultado esperado:

```text
chaves iniciando com escola_a_cache_
chaves iniciando com escola_b_cache_
```

Se nao aparecer nada, pode ser que o cache ainda nao tenha sido usado ou que o mapeamento ainda nao esteja aplicado no painel do Moodle.

## Etapa 18: Verificar consumo do Redis

Execute:

```sh
docker exec moodle_redis redis-cli INFO memory
```

Esse comando mostra informacoes de memoria do Redis.

Campos importantes:

```text
used_memory_human
used_memory_peak_human
mem_fragmentation_ratio
```

Verifique estatisticas gerais:

```sh
docker exec moodle_redis redis-cli INFO stats
```

Verifique quantidade total de chaves no database `0`:

```sh
docker exec moodle_redis redis-cli DBSIZE
```

Esses comandos ajudam a entender se o Redis esta crescendo demais.

## Etapa 19: Confirmar isolamento entre instituicoes

Rode:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_a_*' | head -n 20
```

Depois:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_b_*' | head -n 20
```

Resultado correto:

```text
As chaves da escola A comecam com escola_a_
As chaves da escola B comecam com escola_b_
```

Resultado incorreto:

```text
escola A e escola B usando o mesmo prefixo
chaves sem prefixo claro
chaves de sessao misturadas com cache
```

Se houver mistura, revise:

```sh
grep '^MOODLE_REDIS' secrets/escola-a.local.env
```

```sh
grep '^MOODLE_REDIS' secrets/escola-b.local.env
```

E revise tambem a configuracao de cache feita pelo painel administrativo do Moodle.

## Etapa 20: Reiniciar containers depois da configuracao

Depois de validar a configuracao, reinicie os containers Moodle:

```sh
docker compose -f docker-compose.instituicoes.yml restart
```

Verifique status:

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

Verifique logs:

```sh
docker logs moodle_escola_a --tail 80
```

```sh
docker logs moodle_escola_b --tail 80
```

O Redis deve continuar rodando:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

## Etapa 21: Parar o ambiente sem apagar dados

Para parar apenas as instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml down
```

Para parar a infraestrutura:

```sh
docker compose -f docker-compose.infra.yml down
```

Esses comandos removem containers, mas preservam volumes.

Ou seja, estes dados continuam:

```text
moodle_db_data
moodle_redis_data
moodledata_escola_a
moodledata_escola_b
```

## Etapa 22: Limpar somente chaves Redis de teste

Para remover apenas chaves de teste criadas neste passo:

```sh
docker exec moodle_redis redis-cli DEL escola_a_teste escola_b_teste
```

Para listar chaves de teste restantes:

```sh
docker exec moodle_redis redis-cli --scan --pattern '*_teste'
```

Nao use `FLUSHALL` em ambiente compartilhado.

Este comando apagaria todas as chaves de todas as instituicoes:

```sh
docker exec moodle_redis redis-cli FLUSHALL
```

Use `FLUSHALL` somente em laboratorio descartavel e quando voce tiver certeza de que nao ha dados importantes no Redis.

## Etapa 23: Checklist final

Confirme:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado:

```text
PONG
```

Confirme a extensao PHP Redis:

```sh
docker exec moodle_escola_a php -m | grep -i '^redis$'
```

```sh
docker exec moodle_escola_b php -m | grep -i '^redis$'
```

Resultado:

```text
redis
```

Confirme variaveis:

```sh
docker exec moodle_escola_a printenv | grep '^MOODLE_REDIS'
```

```sh
docker exec moodle_escola_b printenv | grep '^MOODLE_REDIS'
```

Confirme URLs publicas usadas pelo entrypoint:

```sh
docker exec moodle_escola_a printenv | grep '^MOODLE_URL'
```

```sh
docker exec moodle_escola_b printenv | grep '^MOODLE_URL'
```

Confirme o arquivo de `Alias` criado no Apache:

```sh
docker exec moodle_escola_a test -f /etc/apache2/conf-enabled/moodle-public-path.conf
```

```sh
docker exec moodle_escola_b test -f /etc/apache2/conf-enabled/moodle-public-path.conf
```

Confirme as rotas do Caddy:

```sh
sed -n '1,120p' proxy/Caddyfile.local
```

Confirme prefixos:

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_a_*' | head
```

```sh
docker exec moodle_redis redis-cli --scan --pattern 'escola_b_*' | head
```

Confirme logs:

```sh
docker logs moodle_escola_a --tail 80
```

```sh
docker logs moodle_escola_b --tail 80
```

## Problemas comuns

### `Class "Redis" not found`

Causa provavel:

```text
A extensao PHP redis nao esta instalada na imagem Moodle.
```

Verifique:

```sh
docker exec moodle_escola_a php -m | grep -i redis
```

Corrija seguindo a etapa 8.

### `Connection refused`

Causa provavel:

```text
O container Moodle nao conseguiu acessar o Redis.
```

Verifique:

```sh
docker exec moodle_redis redis-cli ping
```

```sh
docker network inspect moodle_net
```

Confirme que `moodle_redis` e os containers Moodle estao na mesma rede.

### Nenhuma chave aparece no Redis

Possiveis causas:

- Moodle ainda nao gerou sessao;
- usuario ainda nao acessou ou logou;
- container Moodle ainda usa imagem antiga;
- `config.php` atualizado nao foi copiado para a imagem;
- containers nao foram recriados depois do rebuild.

Comandos uteis:

```sh
docker compose -f docker-compose.yml build moodle
```

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

### Escola A e escola B usam o mesmo prefixo

Causa:

```text
MOODLE_REDIS_PREFIX repetido nos arquivos .env.
```

Verifique:

```sh
grep '^MOODLE_REDIS_PREFIX' secrets/escola-a.local.env
```

```sh
grep '^MOODLE_REDIS_PREFIX' secrets/escola-b.local.env
```

Corrija para:

```env
MOODLE_REDIS_PREFIX=escola_a_
```

e:

```env
MOODLE_REDIS_PREFIX=escola_b_
```

Depois recrie os containers:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

### `http://localhost:8088/i/escola-a/` nao abre o Moodle

Possiveis causas:

- `proxy/Caddyfile.local` nao tem a rota `/i/escola-a/*`;
- o proxy nao foi recriado depois da alteracao no `Caddyfile`;
- `moodle_escola_a` nao esta na rede `moodle_net`;
- `MOODLE_URL` nao aponta para `http://localhost:8088/i/escola-a`.

Verifique:

```sh
sed -n '1,120p' proxy/Caddyfile.local
```

```sh
docker compose -f docker-compose.infra.yml ps
```

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

```sh
docker exec moodle_escola_a printenv | grep '^MOODLE_URL'
```

Se o `Caddyfile` estiver correto, recrie o proxy:

```sh
docker compose -f docker-compose.infra.yml up -d --force-recreate proxy
```

### `Invalid MOODLE public path`

Causa provavel:

```text
MOODLE_PUBLIC_PATH ou o path de MOODLE_URL tem caracteres fora do padrao aceito pelo entrypoint.
```

O entrypoint aceita apenas letras, numeros, `/`, `_` e `-` no path publico.

Valores validos:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
MOODLE_PUBLIC_PATH=/i/escola-a
```

Valores problematicos:

```env
MOODLE_PUBLIC_PATH=/i/escola a
MOODLE_PUBLIC_PATH=/i/escola.a
```

Depois de corrigir o `.env`, recrie o container da instituicao:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

## Rollback deste passo

Se precisar voltar atras temporariamente, remova ou comente as variaveis Redis nos arquivos:

```text
secrets/escola-a.local.env
secrets/escola-b.local.env
```

Comente estas linhas:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

e:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_b_
```

Depois recrie os containers:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

O bloco do `config.php` foi escrito para ativar Redis somente quando `MOODLE_REDIS_HOST` existir.

Sem essa variavel, o Moodle volta a usar o comportamento padrao de sessao.

## Recomendacao para producao

Para producao:

- use senha no Redis se ele estiver fora de uma rede privada controlada;
- nao exponha a porta `6379` publicamente;
- mantenha o Redis acessivel apenas pela rede interna;
- use prefixos imutaveis por instituicao;
- monitore memoria do Redis;
- defina politica de persistencia conforme criticidade;
- faca teste de carga antes de colocar muitos clientes no mesmo Redis;
- nao use `FLUSHALL` em Redis compartilhado.

Exemplo de variaveis futuras com senha:

```env
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PASSWORD=senha-forte-do-redis
MOODLE_REDIS_PREFIX=escola_a_
```

Se o Redis for gerenciado por provedor cloud, valide:

- TLS;
- usuario/senha;
- politica de memoria;
- limite de conexoes;
- metricas;
- backups ou persistencia;
- latencia entre Moodle e Redis.
