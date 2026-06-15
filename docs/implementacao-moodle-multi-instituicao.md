# Implementacao de Moodle por instituicao com infraestrutura compartilhada

## Objetivo

Implementar uma arquitetura para atender varias instituicoes no mesmo projeto Docker, mantendo uma instalacao Moodle separada para cada instituicao, mas compartilhando os componentes mais pesados da infraestrutura.

A recomendacao final e:

- 1 proxy reverso compartilhado;
- 1 servidor MariaDB ou PostgreSQL compartilhado;
- 1 Redis compartilhado;
- 1 servico de monitoramento;
- 1 mecanismo central de backup;
- 1 imagem Docker Moodle padronizada;
- para cada instituicao, 1 container Moodle, 1 banco logico, 1 usuario de banco, 1 volume `moodledata`, 1 arquivo de secrets, 1 slug publico e 1 ID interno imutavel.

Esse modelo evita multilocacao dentro de uma unica instalacao Moodle e tambem evita duplicar MariaDB, Redis, proxy e workers auxiliares para cada cliente pequeno.

Para reduzir custo com hospedagem e evitar cobranca por subdominio, a URL publica das instituicoes deve usar um unico dominio com um identificador legivel no caminho. O formato recomendado e:

```text
https://seudominio.com/i/escola-a
https://seudominio.com/i/escola-b
https://seudominio.com/i/escola-c
```

O `slug` publico, como `escola-a`, deve ser amigavel para suporte e comunicacao. Internamente, cada instituicao tambem deve manter um ID ou hash imutavel, usado em registros, automacoes, auditoria e integracoes. Assim, a URL pode continuar humana sem depender dela como chave tecnica definitiva.

## Estado atual do projeto

O projeto atual possui uma composicao simples:

- `db`: um container MariaDB;
- `moodle`: um container Moodle baseado em `php:8.3-apache`;
- `cron`: um container permanente executando o cron do Moodle;
- `moodle/config.php`: configuracao fixa para uma unica instalacao;
- `moodledata`: um unico volume compartilhado entre `moodle` e `cron`.

Para suportar varias instituicoes, essa estrutura deve ser evoluida para separar o Moodle de cada instituicao e manter compartilhados apenas os servicos de infraestrutura.

## Arquitetura alvo

```text
Internet
   |
Proxy reverso compartilhado
   |
   +-- seudominio.com/i/escola-a -> moodle_escola_a
   +-- seudominio.com/i/escola-b -> moodle_escola_b
   +-- seudominio.com/i/escola-c -> moodle_escola_c

moodle_escola_a \
moodle_escola_b  +--> Banco compartilhado: moodle_escola_a, moodle_escola_b, moodle_escola_c
moodle_escola_c /

moodle_escola_a \
moodle_escola_b  +--> Redis compartilhado com prefixos exclusivos
moodle_escola_c /
```

Cada instituicao deve ter:

- container Moodle proprio;
- slug publico proprio, por exemplo `escola-a`;
- ID ou hash interno imutavel;
- URL publica propria dentro do dominio unico, por exemplo `https://seudominio.com/i/escola-a`;
- banco logico proprio;
- usuario de banco proprio;
- senha propria;
- volume `moodledata` proprio;
- prefixo Redis proprio;
- logs identificaveis por instituicao;
- limites de CPU e memoria proprios.

Devem ser compartilhados:

- imagem Docker do Moodle;
- proxy reverso;
- MariaDB ou PostgreSQL;
- Redis;
- rede Docker interna;
- pipeline de build e atualizacao;
- monitoramento;
- backups;
- agendamento central do cron.

## Passo 1: Padronizar a imagem Moodle

Manter uma unica imagem para todas as instituicoes, por exemplo:

```text
moodle:2026.06.1
moodle:2026.06.2
moodle:2026.07.1
```

Essa imagem deve conter:

- versao fixa do Moodle;
- extensoes PHP exigidas;
- plugins homologados;
- tema-base;
- OPcache;
- configuracao padrao de PHP;
- configuracao padrao de PHP-FPM.

No projeto atual, o `moodle/Dockerfile` usa `php:8.3-apache`. Para a arquitetura recomendada, o melhor caminho e migrar a imagem para PHP-FPM e deixar HTTP/TLS com o proxy reverso.

Exemplo de direcao para a imagem:

```dockerfile
FROM php:8.3-fpm

# Instalar dependencias, extensoes PHP, Moodle, php.ini e configuracao do PHP-FPM.
# A imagem deve ser igual para todas as instituicoes.
```

Se a migracao para PHP-FPM for feita em etapa posterior, ainda e possivel iniciar a separacao usando a imagem Apache atual, desde que cada instituicao tenha seu proprio container, banco, volume e configuracao.

## Passo 2: Transformar `config.php` em configuracao por variaveis

O `moodle/config.php` atual possui valores fixos:

```php
$CFG->dbhost = 'db';
$CFG->dbname = 'moodle';
$CFG->dbuser = 'moodle';
$CFG->dbpass = 'moodlepass';
$CFG->wwwroot = 'http://localhost:8080';
$CFG->dataroot = '/var/www/moodledata';
```

Esses valores devem vir de variaveis de ambiente ou secrets por instituicao.

Variaveis recomendadas:

```text
MOODLE_URL
MOODLE_DB_HOST
MOODLE_DB_NAME
MOODLE_DB_USER
MOODLE_DB_PASSWORD
MOODLE_DATAROOT
MOODLE_REDIS_HOST
MOODLE_REDIS_PORT
MOODLE_REDIS_PREFIX
MOODLE_PUBLIC_SLUG
MOODLE_TENANT_ID
```

Exemplo conceitual para o `config.php`:

```php
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('MOODLE_DB_HOST') ?: 'db';
$CFG->dbname    = getenv('MOODLE_DB_NAME');
$CFG->dbuser    = getenv('MOODLE_DB_USER');
$CFG->dbpass    = getenv('MOODLE_DB_PASSWORD');
$CFG->prefix    = 'mdl_';

$CFG->wwwroot   = getenv('MOODLE_URL');
$CFG->dataroot  = getenv('MOODLE_DATAROOT') ?: '/var/www/moodledata';
$CFG->admin     = 'admin';

if (getenv('MOODLE_PUBLIC_SLUG')) {
    $sessionSlug = preg_replace('/[^a-zA-Z0-9_]/', '_', getenv('MOODLE_PUBLIC_SLUG'));
    $CFG->sessioncookie = 'MoodleSession_' . $sessionSlug;
}
```

Importante: o mesmo arquivo `config.php` pode existir na imagem de todas as instituicoes, desde que os valores variem por ambiente.

Quando a instituicao estiver atras de um caminho como `/i/escola-a`, o `MOODLE_URL` deve incluir esse caminho completo. Exemplo: `https://seudominio.com/i/escola-a`. Isso faz o Moodle gerar links, redirecionamentos e URLs de assets ja dentro da rota correta.

## Passo 3: Separar a infraestrutura compartilhada

Criar uma composicao base para os servicos compartilhados, por exemplo `docker-compose.infra.yml`.

Servicos iniciais:

```yaml
services:
  db:
    image: mariadb:10.11
    container_name: moodle_db
    restart: unless-stopped
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb_file_per_table=1
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - moodle_net

  redis:
    image: redis:7-alpine
    container_name: moodle_redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    networks:
      - moodle_net

  proxy:
    image: caddy:2-alpine
    container_name: moodle_proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./proxy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - moodle_net

volumes:
  db_data:
  redis_data:
  caddy_data:
  caddy_config:

networks:
  moodle_net:
    driver: bridge
```

O proxy pode ser Caddy, Traefik ou Nginx. A escolha deve considerar automacao de certificados, familiaridade da equipe e estrategia de deploy.

## Passo 4: Criar bancos e usuarios por instituicao

Cada instituicao deve possuir um banco logico e um usuario exclusivo.

Exemplo para MariaDB:

```sql
CREATE DATABASE moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-forte-escola-a';

GRANT ALL PRIVILEGES ON moodle_escola_a.*
  TO 'moodle_escola_a'@'%';

FLUSH PRIVILEGES;
```

Regras:

- uma instituicao nao deve conhecer credenciais de outra;
- o usuario de uma instituicao deve acessar somente o seu proprio banco;
- clientes maiores podem ser migrados depois para outro servidor de banco sem alterar o desenho geral.

## Passo 5: Criar um servico Moodle por instituicao

Criar um arquivo de composicao para as instituicoes, por exemplo `docker-compose.instituicoes.yml`.

Exemplo com duas instituicoes:

```yaml
services:
  moodle_escola_a:
    image: moodle:2026.06.1
    container_name: moodle_escola_a
    restart: unless-stopped
    env_file:
      - ./secrets/escola-a.env
    volumes:
      - moodledata_escola_a:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

  moodle_escola_b:
    image: moodle:2026.06.1
    container_name: moodle_escola_b
    restart: unless-stopped
    env_file:
      - ./secrets/escola-b.env
    volumes:
      - moodledata_escola_b:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_a:
  moodledata_escola_b:

networks:
  moodle_net:
    external: true
```

Exemplo de `secrets/escola-a.env`:

```env
MOODLE_URL=https://seudominio.com/i/escola-a
MOODLE_PUBLIC_SLUG=escola-a
MOODLE_TENANT_ID=8f3b2a510b484f6f8b0d9c7a1e2d4f90
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-forte-escola-a
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

Arquivos reais de secrets nao devem ser versionados.

## Passo 6: Configurar Redis com prefixos exclusivos

O Redis pode ser compartilhado, mas cada Moodle deve usar prefixos diferentes para evitar colisao de cache e sessoes.

No `config.php`, configurar o Redis usando variaveis:

```php
$redisHost = getenv('MOODLE_REDIS_HOST');
$redisPrefix = getenv('MOODLE_REDIS_PREFIX');

if ($redisHost && $redisPrefix) {
    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = $redisHost;
    $CFG->session_redis_port = (int) (getenv('MOODLE_REDIS_PORT') ?: 6379);
    $CFG->session_redis_database = 0;
    $CFG->session_redis_prefix = $redisPrefix . 'session_';

    $CFG->cachestores = [
        'redis' => [
            'name' => 'redis',
            'plugin' => 'redis',
            'configuration' => [
                'server' => $redisHost . ':' . (getenv('MOODLE_REDIS_PORT') ?: 6379),
                'prefix' => $redisPrefix . 'cache_',
            ],
        ],
    ];
}
```

Validar os parametros exatos conforme a versao do Moodle e o plugin de cache Redis disponivel na imagem.

## Passo 7: Configurar o proxy reverso

O dominio publico deve apontar para o proxy compartilhado. Dentro dele, cada caminho `/i/{slug}` deve ser roteado para o container Moodle da respectiva instituicao.

Usar um prefixo fixo como `/i/` e preferivel a usar diretamente `/{slug}`, porque reduz conflito com rotas internas do Moodle, como `/login`, `/theme`, `/pluginfile.php` e `/admin`.

Exemplo conceitual com Caddy:

```caddyfile
seudominio.com {
    redir /i/escola-a /i/escola-a/
    redir /i/escola-b /i/escola-b/

    handle_path /i/escola-a/* {
        reverse_proxy moodle_escola_a:80
    }

    handle_path /i/escola-b/* {
        reverse_proxy moodle_escola_b:80
    }
}
```

Nesse modelo, o proxy recebe `https://seudominio.com/i/escola-a/login/index.php`, remove o prefixo `/i/escola-a` antes de encaminhar ao container e o Moodle continua com `$CFG->wwwroot = 'https://seudominio.com/i/escola-a'`.

Pontos de validacao obrigatorios:

- login e logout;
- redirecionamentos apos login;
- carregamento de CSS, JS, imagens e temas;
- links para arquivos via `pluginfile.php`;
- chamadas Ajax;
- cron;
- URLs enviadas por e-mail;
- cookies e sessoes.

Como todas as instituicoes usam o mesmo host, cada Moodle deve ter identificadores de sessao/cookie exclusivos, por exemplo derivados do `MOODLE_PUBLIC_SLUG` ou do `MOODLE_TENANT_ID`. Isso evita colisao de sessoes entre instituicoes acessadas no mesmo navegador.

Se a imagem for migrada para PHP-FPM puro, o proxy precisara de uma camada HTTP que converse com FPM, normalmente Nginx + FastCGI, ou uma imagem Moodle que ja inclua o servidor web adequado. Nesse caso, o proxy publico continua compartilhado e os containers Moodle continuam isolados por instituicao.

## Passo 8: Substituir o container permanente de cron por agendamento central

O projeto atual possui um servico `cron` permanente. Em varias instituicoes, nao e recomendado criar um container de cron permanente para cada uma.

Criar um script central, por exemplo `scripts/run-moodle-crons.sh`, que execute:

```sh
docker exec moodle_escola_a php /var/www/html/admin/cli/cron.php
docker exec moodle_escola_b php /var/www/html/admin/cli/cron.php
docker exec moodle_escola_c php /var/www/html/admin/cli/cron.php
```

Agendar esse script no host, preferencialmente distribuindo as execucoes ao longo do minuto:

```text
00s: escolas 1 a 5
15s: escolas 6 a 10
30s: escolas 11 a 15
45s: escolas 16 a 20
```

Regras:

- cada Moodle precisa executar seu proprio cron;
- evitar iniciar todos os crons ao mesmo tempo;
- limitar concorrencia se o numero de instituicoes crescer;
- monitorar tarefas pendentes e tempo de execucao.

## Passo 9: Ajustar PHP-FPM para economia de memoria

Para instituicoes pequenas, usar PHP-FPM sob demanda:

```ini
pm = ondemand
pm.max_children = 3
pm.process_idle_timeout = 20s
pm.max_requests = 500
```

Para instituicoes medias ou com uso constante, considerar:

```ini
pm = dynamic
pm.max_children = 8
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 4
pm.max_requests = 500
```

Nao definir `pm.max_children` de forma arbitraria. Usar a formula:

```text
max_children =
(RAM disponivel para o container - baseline - OPcache)
/ consumo medio ou P95 de um processo PHP
```

Exemplo:

```text
RAM do container:              1200 MB
Baseline + OPcache:             300 MB
Memoria disponivel workers:     900 MB
P95 de um worker PHP:           180 MB

900 / 180 = 5 workers
```

Nesse caso, `pm.max_children = 5` seria um ponto inicial para testes.

## Passo 10: Definir limites por instituicao

Usar limites para reduzir risco de uma instituicao consumir todos os recursos do host.

Exemplo:

```yaml
cpus: "1.0"
mem_limit: 1.5g
mem_reservation: 512m
```

Regras:

- `mem_limit` e teto, nao consumo permanente;
- limites muito baixos podem causar encerramento por falta de memoria;
- acompanhar CPU, memoria, latencia e erros antes de reduzir limites;
- clientes maiores podem receber limites maiores ou infraestrutura dedicada.

## Passo 11: Backups centralizados

O backup de cada instituicao deve incluir:

- dump do banco logico;
- volume `moodledata` da instituicao;
- arquivo de secrets;
- versao da imagem Moodle em uso;
- configuracao do proxy para a rota `/i/{slug}`;
- registro do slug publico e do ID interno imutavel.

Evitar backup completo de containers. O container deve ser descartavel; o que precisa ser preservado sao dados, secrets e versao da imagem.

Exemplo de politica:

- backup diario de bancos;
- backup incremental ou sincronizacao do `moodledata`;
- retencao separada para clientes com contrato especial;
- teste periodico de restore em ambiente isolado.

## Passo 12: Monitoramento minimo

Monitorar por instituicao:

- CPU e memoria do container;
- conexoes com o banco;
- tempo P95 e P99 de resposta;
- erros HTTP;
- uso do volume `moodledata`;
- tamanho do banco;
- quantidade e duracao dos crons;
- tarefas pendentes;
- consumo do Redis por prefixo quando possivel.

Monitorar na infraestrutura compartilhada:

- uso do buffer pool do banco;
- I/O de disco;
- conexoes ativas;
- locks e queries lentas;
- memoria e evictions do Redis;
- disponibilidade do proxy;
- validade dos certificados TLS.

## Passo 13: Processo para adicionar uma nova instituicao

Checklist operacional:

1. Definir slug publico da instituicao, por exemplo `escola-a`.
2. Gerar ID ou hash interno imutavel para a instituicao.
3. Criar banco `moodle_escola_a`.
4. Criar usuario `moodle_escola_a`.
5. Conceder permissoes apenas no banco da instituicao.
6. Criar arquivo de secrets `secrets/escola-a.env`.
7. Criar volume `moodledata_escola_a`.
8. Adicionar servico `moodle_escola_a` ao Compose de instituicoes.
9. Adicionar rota `https://seudominio.com/i/escola-a` no proxy reverso.
10. Subir o container.
11. Executar instalacao inicial do Moodle.
12. Adicionar a instituicao ao agendamento central de cron.
13. Incluir banco e `moodledata` na rotina de backup.
14. Incluir container e rota publica no monitoramento.

## Passo 14: Estrategia de atualizacao

Todas as instituicoes devem usar a mesma imagem homologada.

Fluxo recomendado:

1. Criar nova imagem, por exemplo `moodle:2026.07.1`.
2. Testar em ambiente de homologacao.
3. Atualizar uma instituicao piloto.
4. Validar login, cursos, uploads, cron, cache e plugins.
5. Atualizar as demais instituicoes em lotes.
6. Manter plano de rollback com dump do banco e snapshot do `moodledata`.

Evitar:

- plugins diferentes por instituicao sem processo de homologacao;
- atualizacao manual site por site;
- imagens com codigo diferente para cada cliente;
- alteracoes diretas dentro de containers em producao.

## Passo 15: Quando isolar mais

O modelo compartilhado atende bem clientes pequenos e medios. Migrar uma instituicao para infraestrutura mais isolada quando houver:

- muitos usuarios simultaneos;
- quizzes grandes e simultaneos;
- relatorios pesados frequentes;
- crescimento elevado de `moodledata`;
- exigencia contratual ou regulatoria;
- impacto perceptivel em outros clientes;
- necessidade de janela de manutencao propria.

Opcoes de evolucao:

- banco dedicado;
- Redis dedicado;
- storage dedicado;
- host dedicado;
- stack completa dedicada.

## O que evitar inicialmente

Evitar no inicio:

- um MariaDB por instituicao pequena;
- um Redis por instituicao pequena;
- um proxy por instituicao;
- uma stack completa para cada cliente;
- um unico Moodle para todas as instituicoes usando apenas categorias e grupos;
- permitir plugins livres por instituicao;
- backups de containers em vez de dados;
- crons simultaneos para todas as instituicoes;
- Kubernetes apenas para resolver isolamento entre instituicoes.

## Resultado esperado

Ao final da implementacao, o projeto deve permitir operar varias instituicoes com bom isolamento logico e operacional:

- cada instituicao tem seu proprio Moodle, banco, `moodledata`, secrets, slug publico e ID interno;
- cada instituicao e acessada por uma URL humana no dominio unico, usando `/i/{slug}`;
- cada instituicao mantem um ID interno imutavel para automacoes e auditoria;
- a infraestrutura pesada e compartilhada;
- a imagem Moodle e padronizada;
- o custo cresce principalmente com uso real de PHP, armazenamento e banco, nao com a duplicacao completa da stack;
- clientes grandes podem ser promovidos para infraestrutura dedicada sem mudar o modelo geral.
