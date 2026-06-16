# Passo 3: Separar a infraestrutura compartilhada

## Objetivo deste passo

Neste passo, o objetivo e separar os servicos de infraestrutura que serao compartilhados entre varias instituicoes Moodle.

No estado atual, o arquivo `docker-compose.yml` mistura tudo:

- banco MariaDB;
- container web do Moodle;
- container de cron do Moodle;
- volumes;
- rede Docker.

Para a arquitetura multi-instituicao, a infraestrutura pesada deve ficar em uma composicao propria. Neste passo vamos criar um arquivo separado:

```text
docker-compose.infra.yml
```

Esse arquivo vai subir apenas:

- `db`: MariaDB compartilhado;
- `redis`: Redis compartilhado;
- `proxy`: proxy reverso compartilhado com Caddy;
- volumes persistentes da infraestrutura;
- rede Docker compartilhada.

O Moodle de cada instituicao sera conectado a essa infraestrutura em passos posteriores.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- separar responsabilidades entre arquivos Compose;
- entender redes Docker nomeadas;
- entender volumes Docker nomeados;
- subir apenas parte da arquitetura;
- validar containers em execucao;
- consultar logs;
- executar comandos dentro de containers;
- testar conectividade entre containers;
- testar um proxy reverso local;
- parar containers sem apagar dados;
- remover containers e volumes somente quando desejar limpar o ambiente.

## Resultado esperado

Ao final deste passo, voce tera estes containers rodando:

```text
moodle_db
moodle_redis
moodle_proxy
```

E estes recursos Docker criados:

```text
Rede:
  moodle_net

Volumes:
  moodle_db_data
  moodle_redis_data
  moodle_caddy_data
  moodle_caddy_config
```

O proxy local devera responder em:

```text
http://localhost:8088
```

## Conceitos rapidos antes dos comandos

### Infraestrutura compartilhada

Infraestrutura compartilhada e o conjunto de servicos usados por varias aplicacoes ou varios clientes.

Neste caso, em vez de criar isto para cada instituicao:

```text
escola-a: MariaDB + Redis + proxy + Moodle
escola-b: MariaDB + Redis + proxy + Moodle
escola-c: MariaDB + Redis + proxy + Moodle
```

Vamos criar:

```text
Infra compartilhada:
  MariaDB
  Redis
  proxy

Instituicoes:
  Moodle escola-a
  Moodle escola-b
  Moodle escola-c
```

Isso reduz consumo de memoria, CPU e complexidade operacional.

### Rede Docker

Uma rede Docker permite que containers conversem entre si usando o nome do servico ou do container.

Exemplo:

```text
moodle_escola_a -> db
moodle_escola_a -> redis
moodle_escola_a -> proxy
```

Dentro da rede Docker, o Moodle nao precisa saber o IP do MariaDB. Ele pode acessar o banco pelo nome:

```text
db
```

### Volume Docker

Um volume Docker guarda dados persistentes fora do ciclo de vida do container.

Isso significa:

- se o container for recriado, os dados continuam;
- se a imagem for atualizada, os dados continuam;
- se voce executar `docker compose down` sem `-v`, os volumes continuam.

Neste passo, o MariaDB e o Redis usarao volumes proprios.

### Proxy reverso

Um proxy reverso recebe a requisicao HTTP do navegador e encaminha para o container correto.

Exemplo futuro:

```text
http://localhost:8088/i/escola-a -> moodle_escola_a
http://localhost:8088/i/escola-b -> moodle_escola_b
```

Neste passo, ainda nao teremos os Moodles por instituicao. O proxy sera criado com uma resposta simples apenas para validar que ele esta funcionando.

## Decisao tecnica deste passo

Para ambiente local, vamos usar:

- MariaDB `10.11`;
- Redis `7-alpine`;
- Caddy `2-alpine`;
- porta local `8088` para HTTP;
- porta local `8443` para HTTPS, reservada para testes posteriores.

Nao vamos usar as portas `80` e `443` neste passo porque elas podem exigir permissao especial ou ja estar ocupadas na sua maquina.

Em producao, a configuracao pode usar:

```yaml
ports:
  - "80:80"
  - "443:443"
```

Localmente, usaremos:

```yaml
ports:
  - "8088:80"
  - "8443:443"
```

## Arquivos envolvidos

Arquivos que serao criados neste passo:

```text
docker-compose.infra.yml
proxy/Caddyfile.local
secrets/infra.local.env
```

Arquivos que nao serao alterados neste passo:

```text
docker-compose.yml
moodle/Dockerfile
moodle/config.php
moodle/php.ini
```

O objetivo e criar a infraestrutura em paralelo, sem quebrar o Compose atual.

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

Liste os arquivos:

```sh
ls
```

Resultado esperado, no minimo:

```text
docker-compose.yml
docs
moodle
secrets
```

Se a pasta `secrets` ainda nao existir, crie:

```sh
mkdir -p secrets
```

## Etapa 2: Verificar se o Docker esta funcionando

Verifique a versao do Docker:

```sh
docker --version
```

Exemplo de resultado esperado:

```text
Docker version 27.x.x
```

Verifique a versao do Docker Compose:

```sh
docker compose version
```

Exemplo de resultado esperado:

```text
Docker Compose version v2.x.x
```

Verifique se o Docker Engine esta respondendo:

```sh
docker info
```

Se aparecer algo parecido com:

```text
Cannot connect to the Docker daemon
```

abra o Docker Desktop e aguarde a inicializacao.

## Etapa 3: Verificar se existe uma stack atual rodando

O projeto atual usa containers com nomes fixos, como:

```text
moodle_db
moodle_app
moodle_cron
```

Antes de subir a nova infraestrutura, confira se algum deles esta rodando:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Se aparecer `moodle_db`, `moodle_app` ou `moodle_cron`, pare a stack atual:

```sh
docker compose down
```

Esse comando remove os containers da stack atual, mas nao apaga os volumes porque nao usamos `-v`.

Confirme novamente:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Se os containers antigos sumiram, voce pode continuar.

## Etapa 4: Criar backup do Compose atual

Mesmo que este passo nao altere `docker-compose.yml`, crie uma copia de seguranca para fins de estudo:

```sh
cp docker-compose.yml docker-compose.yml.bak-passo-03
```

Confira:

```sh
ls docker-compose.yml*
```

Resultado esperado:

```text
docker-compose.yml
docker-compose.yml.bak-passo-03
```

## Etapa 5: Criar arquivo de secrets da infraestrutura

Crie o arquivo:

```sh
touch secrets/infra.local.env
```

Ajuste a permissao:

```sh
chmod 600 secrets/infra.local.env
```

Abra o arquivo em um editor. Se usa VS Code:

```sh
code secrets/infra.local.env
```

Se preferir terminal:

```sh
nano secrets/infra.local.env
```

Cole este conteudo:

```env
MARIADB_ROOT_PASSWORD=rootpass-local
```

Salve o arquivo.

Se estiver usando `nano`:

1. pressione `Ctrl + O`;
2. pressione `Enter`;
3. pressione `Ctrl + X`.

Confira o arquivo:

```sh
sed -n '1,40p' secrets/infra.local.env
```

Resultado esperado:

```text
MARIADB_ROOT_PASSWORD=rootpass-local
```

Confirme a permissao:

```sh
ls -l secrets/infra.local.env
```

Resultado esperado no inicio da linha:

```text
-rw-------
```

Observacao: este arquivo ja deve estar protegido pelo `.gitignore`, porque o projeto ignora `secrets/*.env`.

## Etapa 6: Criar a pasta do proxy

Crie a pasta:

```sh
mkdir -p proxy
```

Confira:

```sh
ls
```

Agora deve existir:

```text
proxy
```

## Etapa 7: Criar o arquivo `proxy/Caddyfile.local`

Crie o arquivo:

```sh
touch proxy/Caddyfile.local
```

Abra no editor:

```sh
code proxy/Caddyfile.local
```

ou:

```sh
nano proxy/Caddyfile.local
```

Cole este conteudo:

```caddyfile
:80 {
    respond "Proxy local da infraestrutura Moodle funcionando" 200
}
```

Salve o arquivo.

Confira:

```sh
sed -n '1,80p' proxy/Caddyfile.local
```

Resultado esperado:

```text
:80 {
    respond "Proxy local da infraestrutura Moodle funcionando" 200
}
```

Neste momento, o Caddy ainda nao encaminha requisicoes para containers Moodle. Ele apenas responde uma mensagem fixa. O roteamento para instituicoes entra em passos posteriores.

## Etapa 8: Criar `docker-compose.infra.yml`

Crie o arquivo:

```sh
touch docker-compose.infra.yml
```

Abra:

```sh
code docker-compose.infra.yml
```

ou:

```sh
nano docker-compose.infra.yml
```

Cole este conteudo:

```yaml
services:
  db:
    image: mariadb:10.11
    container_name: moodle_db
    restart: unless-stopped
    env_file:
      - ./secrets/infra.local.env
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb_file_per_table=1
    volumes:
      - moodle_db_data:/var/lib/mysql
    networks:
      - moodle_net
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -h 127.0.0.1 -uroot -p$${MARIADB_ROOT_PASSWORD} || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10

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

  proxy:
    image: caddy:2-alpine
    container_name: moodle_proxy
    restart: unless-stopped
    ports:
      - "8088:80"
      - "8443:443"
    volumes:
      - ./proxy/Caddyfile.local:/etc/caddy/Caddyfile:ro
      - moodle_caddy_data:/data
      - moodle_caddy_config:/config
    networks:
      - moodle_net
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

volumes:
  moodle_db_data:
    name: moodle_db_data
  moodle_redis_data:
    name: moodle_redis_data
  moodle_caddy_data:
    name: moodle_caddy_data
  moodle_caddy_config:
    name: moodle_caddy_config

networks:
  moodle_net:
    name: moodle_net
    driver: bridge
```

Salve o arquivo.

## Etapa 9: Entender o `docker-compose.infra.yml`

O servico `db` cria o MariaDB compartilhado:

```yaml
db:
  image: mariadb:10.11
  container_name: moodle_db
```

O nome `moodle_db` facilita comandos manuais, por exemplo:

```sh
docker exec moodle_db mariadb --version
```

O trecho abaixo carrega a senha do root a partir do arquivo de secrets:

```yaml
env_file:
  - ./secrets/infra.local.env
```

O volume abaixo guarda os dados do banco:

```yaml
volumes:
  - moodle_db_data:/var/lib/mysql
```

O servico `redis` cria o Redis compartilhado:

```yaml
redis:
  image: redis:7-alpine
  container_name: moodle_redis
```

O comando abaixo ativa persistencia AOF no Redis:

```yaml
command:
  - redis-server
  - --appendonly
  - "yes"
```

O servico `proxy` cria o Caddy:

```yaml
proxy:
  image: caddy:2-alpine
  container_name: moodle_proxy
```

As portas locais sao:

```yaml
ports:
  - "8088:80"
  - "8443:443"
```

Isso significa:

```text
localhost:8088 -> porta 80 dentro do container Caddy
localhost:8443 -> porta 443 dentro do container Caddy
```

A rede compartilhada tem nome fixo:

```yaml
networks:
  moodle_net:
    name: moodle_net
    driver: bridge
```

Esse nome fixo e importante porque os futuros containers Moodle das instituicoes poderao entrar nessa mesma rede.

## Etapa 10: Validar a sintaxe do Compose

Execute:

```sh
docker compose -f docker-compose.infra.yml config
```

Esse comando nao sobe containers. Ele apenas valida e imprime a configuracao final interpretada pelo Docker Compose.

Resultado esperado:

- o comando termina sem erro;
- aparecem os servicos `db`, `redis` e `proxy`;
- aparecem os volumes `moodle_db_data`, `moodle_redis_data`, `moodle_caddy_data`, `moodle_caddy_config`;
- aparece a rede `moodle_net`.

Se aparecer erro de YAML, revise indentacao. YAML depende de espacos. Nao use tabs.

## Etapa 11: Baixar as imagens sem subir os containers

Execute:

```sh
docker compose -f docker-compose.infra.yml pull
```

Esse comando baixa as imagens:

```text
mariadb:10.11
redis:7-alpine
caddy:2-alpine
```

Confira as imagens:

```sh
docker images
```

Voce deve ver linhas contendo:

```text
mariadb
redis
caddy
```

Se o comando falhar com erro de rede, verifique a conexao com a internet e se o Docker Desktop esta logado/ativo.

## Etapa 12: Subir a infraestrutura

Execute:

```sh
docker compose -f docker-compose.infra.yml up -d
```

Significado:

- `docker compose`: usa Docker Compose;
- `-f docker-compose.infra.yml`: escolhe o arquivo de Compose;
- `up`: cria e inicia os containers;
- `-d`: roda em segundo plano.

Resultado esperado:

```text
Container moodle_db      Started
Container moodle_redis   Started
Container moodle_proxy   Started
```

## Etapa 13: Ver containers em execucao

Execute:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Resultado esperado:

```text
NAMES          STATUS                    PORTS
moodle_db      Up ... healthy            3306/tcp
moodle_redis   Up ... healthy            6379/tcp
moodle_proxy   Up ...                    0.0.0.0:8088->80/tcp, 0.0.0.0:8443->443/tcp
```

O status `healthy` pode demorar alguns segundos para aparecer.

Se ainda estiver como `starting`, aguarde e execute novamente:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Etapa 14: Ver logs da infraestrutura

Ver logs de todos os servicos:

```sh
docker compose -f docker-compose.infra.yml logs
```

Ver logs acompanhando em tempo real:

```sh
docker compose -f docker-compose.infra.yml logs -f
```

Para sair do modo acompanhamento, pressione:

```text
Ctrl + C
```

Ver logs apenas do MariaDB:

```sh
docker compose -f docker-compose.infra.yml logs db
```

Ver logs apenas do Redis:

```sh
docker compose -f docker-compose.infra.yml logs redis
```

Ver logs apenas do proxy:

```sh
docker compose -f docker-compose.infra.yml logs proxy
```

## Etapa 15: Testar o proxy local

Execute:

```sh
curl http://localhost:8088
```

Resultado esperado:

```text
Proxy local da infraestrutura Moodle funcionando
```

Se quiser ver os headers HTTP:

```sh
curl -i http://localhost:8088
```

Resultado esperado no inicio:

```text
HTTP/1.1 200 OK
```

Se aparecer erro de conexao recusada, verifique se `moodle_proxy` esta rodando:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Se aparecer erro de porta ocupada, provavelmente outro processo esta usando `8088`. Nesse caso, altere o Compose:

```yaml
ports:
  - "8090:80"
  - "8443:443"
```

Depois recrie o proxy:

```sh
docker compose -f docker-compose.infra.yml up -d
```

E teste:

```sh
curl http://localhost:8090
```

## Etapa 16: Testar o MariaDB

Execute:

```sh
docker exec moodle_db mariadb --version
```

Resultado esperado:

```text
mariadb  Ver ...
```

Agora teste login como root:

```sh
docker exec -it moodle_db mariadb -uroot -p
```

Quando pedir senha, digite:

```text
rootpass-local
```

Dentro do prompt do MariaDB, execute:

```sql
SHOW DATABASES;
```

Resultado esperado inclui bancos internos como:

```text
information_schema
mysql
performance_schema
sys
```

Saia do MariaDB:

```sql
exit;
```

Atalho sem entrar no shell interativo:

```sh
docker exec moodle_db mariadb -uroot -prootpass-local -e "SHOW DATABASES;"
```

Observacao: em ambiente real, evite passar senha diretamente na linha de comando, porque ela pode aparecer no historico do terminal. Localmente, para estudo, isso facilita a validacao.

## Etapa 17: Testar o Redis

Execute:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

Grave uma chave de teste:

```sh
docker exec moodle_redis redis-cli set teste:infra ok
```

Resultado esperado:

```text
OK
```

Leia a chave:

```sh
docker exec moodle_redis redis-cli get teste:infra
```

Resultado esperado:

```text
ok
```

Remova a chave:

```sh
docker exec moodle_redis redis-cli del teste:infra
```

Resultado esperado:

```text
(integer) 1
```

## Etapa 18: Verificar a rede Docker

Liste as redes:

```sh
docker network ls
```

Voce deve ver:

```text
moodle_net
```

Inspecione a rede:

```sh
docker network inspect moodle_net
```

Procure pelos containers conectados:

```text
moodle_db
moodle_redis
moodle_proxy
```

## Etapa 19: Testar DNS interno entre containers

O Docker cria DNS interno para containers na mesma rede.

Teste se o proxy consegue resolver o nome `db`:

```sh
docker exec moodle_proxy ping -c 3 db
```

Resultado esperado:

```text
3 packets transmitted, 3 packets received
```

Teste se o proxy consegue resolver o nome `redis`:

```sh
docker exec moodle_proxy ping -c 3 redis
```

Resultado esperado:

```text
3 packets transmitted, 3 packets received
```

Se `ping` nao estiver disponivel na imagem do Caddy, use este teste alternativo com um container temporario:

```sh
docker run --rm --network moodle_net alpine:3.20 ping -c 3 db
```

E:

```sh
docker run --rm --network moodle_net alpine:3.20 ping -c 3 redis
```

Esses comandos criam um container temporario Alpine, conectam na rede `moodle_net`, fazem o teste e removem o container ao final.

## Etapa 20: Verificar os volumes Docker

Liste os volumes:

```sh
docker volume ls
```

Voce deve ver:

```text
moodle_db_data
moodle_redis_data
moodle_caddy_data
moodle_caddy_config
```

Inspecione o volume do banco:

```sh
docker volume inspect moodle_db_data
```

Inspecione o volume do Redis:

```sh
docker volume inspect moodle_redis_data
```

O campo `Mountpoint` mostra onde o Docker guarda os dados fisicamente dentro da area gerenciada pelo Docker Desktop.

## Etapa 21: Reiniciar a infraestrutura

Para reiniciar todos os servicos:

```sh
docker compose -f docker-compose.infra.yml restart
```

Para reiniciar apenas o Redis:

```sh
docker compose -f docker-compose.infra.yml restart redis
```

Para reiniciar apenas o proxy:

```sh
docker compose -f docker-compose.infra.yml restart proxy
```

Confira o estado depois:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Etapa 22: Parar sem apagar containers

Para parar a infraestrutura sem remover containers:

```sh
docker compose -f docker-compose.infra.yml stop
```

Confira:

```sh
docker ps
```

Os containers parados nao aparecem em `docker ps`.

Para ver tambem containers parados:

```sh
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

Para iniciar novamente:

```sh
docker compose -f docker-compose.infra.yml start
```

## Etapa 23: Remover containers sem apagar volumes

Quando quiser remover os containers da infraestrutura, mas manter os dados:

```sh
docker compose -f docker-compose.infra.yml down
```

Isso remove:

- containers;
- rede criada pelo Compose, se nao estiver em uso.

Isso nao remove:

- volumes;
- imagens;
- arquivos do projeto.

Confirme que os volumes continuam:

```sh
docker volume ls
```

Voce ainda deve ver:

```text
moodle_db_data
moodle_redis_data
moodle_caddy_data
moodle_caddy_config
```

Para subir novamente:

```sh
docker compose -f docker-compose.infra.yml up -d
```

## Etapa 24: Limpeza completa do ambiente de teste

Use esta etapa somente se quiser apagar os dados locais da infraestrutura.

Primeiro, remova containers e rede:

```sh
docker compose -f docker-compose.infra.yml down
```

Depois remova os volumes especificos deste passo:

```sh
docker volume rm moodle_db_data
docker volume rm moodle_redis_data
docker volume rm moodle_caddy_data
docker volume rm moodle_caddy_config
```

Confirme:

```sh
docker volume ls
```

Os volumes acima nao devem mais aparecer.

Atencao: remover `moodle_db_data` apaga todos os bancos criados dentro desse MariaDB local.

## Etapa 25: Como voltar para a stack antiga

Se voce quiser voltar ao funcionamento anterior do projeto com `docker-compose.yml`, primeiro pare a infra separada:

```sh
docker compose -f docker-compose.infra.yml down
```

Depois suba a stack antiga:

```sh
docker compose up -d
```

Confira:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Voce deve ver novamente:

```text
moodle_db
moodle_app
moodle_cron
```

## Etapa 26: Problemas comuns

### Erro: container name is already in use

Mensagem comum:

```text
Conflict. The container name "/moodle_db" is already in use
```

Causa: existe outro container com o mesmo nome.

Confira:

```sh
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

Se for a stack antiga, remova os containers antigos sem apagar volumes:

```sh
docker compose down
```

Depois suba a infra:

```sh
docker compose -f docker-compose.infra.yml up -d
```

### Erro: port is already allocated

Mensagem comum:

```text
Bind for 0.0.0.0:8088 failed: port is already allocated
```

Causa: outro processo esta usando a porta `8088`.

Troque no arquivo `docker-compose.infra.yml`:

```yaml
ports:
  - "8090:80"
  - "8443:443"
```

Depois execute:

```sh
docker compose -f docker-compose.infra.yml up -d
```

Teste:

```sh
curl http://localhost:8090
```

### MariaDB fica como unhealthy

Veja os logs:

```sh
docker compose -f docker-compose.infra.yml logs db
```

Confira se `secrets/infra.local.env` existe:

```sh
ls -l secrets/infra.local.env
```

Confira o conteudo:

```sh
sed -n '1,40p' secrets/infra.local.env
```

Deve existir:

```text
MARIADB_ROOT_PASSWORD=rootpass-local
```

### Redis fica como unhealthy

Veja os logs:

```sh
docker compose -f docker-compose.infra.yml logs redis
```

Teste manualmente:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

### Proxy nao responde

Veja os logs:

```sh
docker compose -f docker-compose.infra.yml logs proxy
```

Confira se o arquivo do Caddy existe:

```sh
sed -n '1,80p' proxy/Caddyfile.local
```

Teste a porta:

```sh
curl -i http://localhost:8088
```

## Checklist de conclusao

Considere este passo concluido quando todos os itens abaixo estiverem verdadeiros:

- `docker-compose.infra.yml` existe;
- `proxy/Caddyfile.local` existe;
- `secrets/infra.local.env` existe e esta com permissao restrita;
- `docker compose -f docker-compose.infra.yml config` executa sem erro;
- `docker compose -f docker-compose.infra.yml up -d` sobe os servicos;
- `moodle_db` fica em estado `healthy`;
- `moodle_redis` fica em estado `healthy`;
- `moodle_proxy` fica em execucao;
- `curl http://localhost:8088` retorna a mensagem do proxy;
- `docker exec moodle_db mariadb --version` funciona;
- `docker exec moodle_redis redis-cli ping` retorna `PONG`;
- `docker network ls` mostra `moodle_net`;
- `docker volume ls` mostra os volumes da infraestrutura.

## Proximo passo

Depois deste passo, a infraestrutura compartilhada estara pronta localmente.

O proximo passo tecnico e criar bancos e usuarios por instituicao dentro do MariaDB compartilhado. Isso corresponde ao Passo 4 da arquitetura geral.

