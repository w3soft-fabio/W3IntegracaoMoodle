# Comandos Docker essenciais deste projeto

Este guia e uma referencia operacional para administrar este projeto Moodle com
Docker. Execute os comandos a partir da raiz do repositorio:

```sh
cd "/caminho/para/moodle-docker"
```

Os exemplos usam `escola-modelo`, que existe atualmente no projeto. Ao
trabalhar com outra instituicao, troque:

```text
Servico Compose: moodle_escola_modelo
Container:        moodle_escola_modelo
Volume:           moodledata_escola_modelo
Banco:            valor de MOODLE_DB_NAME no secret da instituicao
```

## 1. Entenda os dois modos do projeto

O repositorio possui duas formas alternativas de execucao.

### Modo simples

Arquivo:

```text
docker-compose.yml
```

Servicos:

```text
db      -> container moodle_db
moodle  -> container moodle_app, publicado em http://localhost:8080
```

Use este modo para estudar ou executar uma unica instalacao local.

Antes da primeira subida, `secrets/local.env` precisa conter todas as
variaveis exigidas pelo bootstrap automatico, nao apenas a conexao com o banco.
Isso inclui identidade do site, administrador e usuario de Web Service. Consulte
`docs/instalacao-limpa-e-compartilhamento.md` para o modelo completo.

### Modo multi-instituicao

Arquivos:

```text
docker-compose.infra.yml
docker-compose.instituicoes.yml
```

A infraestrutura compartilhada possui:

```text
db      -> container moodle_db
redis   -> container moodle_redis
proxy   -> container moodle_proxy, HTTP em http://localhost:8088
```

Cada instituicao possui um servico e um volume de `moodledata` proprios. A
instituicao atual e acessada por:

```text
http://localhost:8088/i/escola-modelo/
```

> **Importante:** nao execute o modo simples e o multi-instituicao ao mesmo
> tempo. Os dois tentam usar o container `moodle_db` e a rede do mesmo projeto.
> Nos comandos abaixo, sempre confira qual arquivo foi informado com `-f`.

## 2. Comandos de consulta rapida

Verificar se Docker e Compose estao instalados e se o daemon esta ativo:

```sh
docker --version
docker compose version
docker info
```

Listar containers em execucao:

```sh
docker ps
```

Listar tambem os containers parados:

```sh
docker ps -a
```

Exibir uma tabela mais util:

```sh
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

Ver uso de CPU e memoria em tempo real:

```sh
docker stats
```

Ver o espaco usado pelo Docker:

```sh
docker system df
```

Listar imagens, volumes e redes:

```sh
docker image ls
docker volume ls
docker network ls
```

## 3. Validar a configuracao antes de subir

Use `--quiet` para apenas validar. Dessa forma, o Compose nao imprime no
terminal os valores expandidos dos arquivos em `secrets/`.

Modo simples:

```sh
docker compose -f docker-compose.yml config --quiet
```

Modo multi-instituicao:

```sh
docker compose -f docker-compose.infra.yml config --quiet
docker compose -f docker-compose.instituicoes.yml config --quiet
```

Listar somente os servicos reconhecidos:

```sh
docker compose -f docker-compose.infra.yml config --services
docker compose -f docker-compose.instituicoes.yml config --services
```

> Evite publicar a saida de `docker compose config`: ela pode conter senhas
> vindas de `env_file`.

## 4. Operacao diaria: modo simples

Criar ou atualizar a stack em segundo plano:

```sh
docker compose -f docker-compose.yml up -d
```

Construir a imagem e subir:

```sh
docker compose -f docker-compose.yml up -d --build
```

Ver o estado dos servicos:

```sh
docker compose -f docker-compose.yml ps
```

Parar sem remover os containers:

```sh
docker compose -f docker-compose.yml stop
```

Iniciar containers que foram parados:

```sh
docker compose -f docker-compose.yml start
```

Reiniciar:

```sh
docker compose -f docker-compose.yml restart
```

Remover os containers e a rede, preservando os volumes:

```sh
docker compose -f docker-compose.yml down
```

## 5. Operacao diaria: modo multi-instituicao

Sempre suba primeiro a infraestrutura e depois as instituicoes:

```sh
docker compose -f docker-compose.infra.yml up -d
docker compose -f docker-compose.instituicoes.yml up -d
```

Ver o estado de cada grupo:

```sh
docker compose -f docker-compose.infra.yml ps
docker compose -f docker-compose.instituicoes.yml ps
```

Subir ou atualizar apenas uma instituicao:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_modelo
```

Parar e iniciar apenas uma instituicao:

```sh
docker compose -f docker-compose.instituicoes.yml stop moodle_escola_modelo
docker compose -f docker-compose.instituicoes.yml start moodle_escola_modelo
```

Reiniciar apenas proxy, banco ou Redis:

```sh
docker compose -f docker-compose.infra.yml restart proxy
docker compose -f docker-compose.infra.yml restart db
docker compose -f docker-compose.infra.yml restart redis
```

Para desligar completamente, pare primeiro as instituicoes e depois a
infraestrutura:

```sh
docker compose -f docker-compose.instituicoes.yml down
docker compose -f docker-compose.infra.yml down
```

O `down` sem `-v` preserva os dados. Os volumes `moodledata_*` deste projeto
tambem sao declarados como externos.

> Nao acrescente `--remove-orphans` aos comandos deste projeto. Infraestrutura
> e instituicoes compartilham o mesmo nome de projeto Compose, e um arquivo pode
> enxergar os servicos do outro como orfaos.

## 6. Quando usar restart, recreate ou build

Use `restart` quando o container apenas precisa reiniciar com a mesma
configuracao:

```sh
docker compose -f docker-compose.instituicoes.yml restart moodle_escola_modelo
```

Alteracoes em `secrets/*.env` nao sao carregadas por `restart`. Recrie o
container:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_modelo
```

Alteracoes em `docker-compose*.yml`, como limites de CPU/memoria, normalmente
sao aplicadas por:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_modelo
```

Alteracoes nos arquivos abaixo exigem uma nova imagem:

```text
moodle/Dockerfile
moodle/config.php
moodle/php.ini
moodle/docker-entrypoint.sh
moodle/bootstrap/provision.php
```

Construir a imagem usada pelas instituicoes:

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
```

Ou usar o servico de build do Compose simples:

```sh
docker compose -f docker-compose.yml build moodle
```

Reconstruir ignorando o cache:

```sh
docker compose -f docker-compose.yml build --no-cache moodle
```

Depois do build, recrie as instituicoes que devem usar a imagem nova:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

## 7. Logs e diagnostico

### Logs pelo Compose

Ultimas 100 linhas da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml logs --tail=100
```

Acompanhar os logs do proxy:

```sh
docker compose -f docker-compose.infra.yml logs -f proxy
```

Acompanhar uma instituicao:

```sh
docker compose -f docker-compose.instituicoes.yml logs -f --tail=100 moodle_escola_modelo
```

Pressione `Ctrl+C` para parar de acompanhar. Isso nao para o container.

### Logs pelo nome do container

```sh
docker logs --tail=200 moodle_escola_modelo
docker logs --since=30m moodle_escola_modelo
docker logs -f moodle_proxy
```

### Inspecao

Ver todos os detalhes de um container:

```sh
docker inspect moodle_escola_modelo
```

Ver estado e healthcheck de forma resumida:

```sh
docker inspect --format '{{json .State}}' moodle_escola_modelo
docker inspect --format '{{json .State.Health}}' moodle_db
```

Ver reinicios, imagem e limites:

```sh
docker inspect --format 'reinicios={{.RestartCount}} imagem={{.Config.Image}} memoria={{.HostConfig.Memory}} cpus={{.HostConfig.NanoCpus}}' moodle_escola_modelo
```

Ver processos em execucao:

```sh
docker top moodle_escola_modelo
```

## 8. Entrar e executar comandos nos containers

Abrir um shell no Moodle:

```sh
docker exec -it moodle_escola_modelo sh
```

Abrir como o usuario do Apache/Moodle:

```sh
docker exec -it -u www-data moodle_escola_modelo sh
```

Pelo Compose:

```sh
docker compose -f docker-compose.instituicoes.yml exec moodle_escola_modelo sh
```

Executar um comando sem abrir shell:

```sh
docker exec moodle_escola_modelo php -v
docker exec moodle_escola_modelo php -m
```

Conferir variaveis nao sensiveis individualmente:

```sh
docker exec moodle_escola_modelo printenv MOODLE_URL
docker exec moodle_escola_modelo printenv MOODLE_DB_HOST
docker exec moodle_escola_modelo printenv MOODLE_DB_NAME
```

> Nao publique `printenv` completo: o ambiente contem senhas e outras
> credenciais.

Copiar um arquivo do container para o host:

```sh
docker cp moodle_escola_modelo:/caminho/no/container ./destino-local
```

Copiar do host para o container:

```sh
docker cp ./arquivo-local moodle_escola_modelo:/tmp/arquivo
```

Arquivos copiados diretamente para o container desaparecem quando ele e
recriado. Mudancas permanentes devem entrar na imagem, no Compose ou em um
volume.

## 9. Comandos administrativos do Moodle

Execute comandos Moodle como `www-data`.

Rodar o cron de uma instituicao:

```sh
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/cron.php
```

Limpar todos os caches:

```sh
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/purge_caches.php
```

Ativar e desativar o modo de manutencao:

```sh
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/maintenance.php --enable
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/maintenance.php --disable
```

Verificar e aplicar upgrades pendentes:

```sh
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/upgrade.php --non-interactive
```

O entrypoint deste projeto ja executa o upgrade e o provisionamento
automaticamente quando o Moodle inicia normalmente.

### Cron centralizado do projeto

Descobrir os tenants ativos:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --discover
```

Conferir o balanceamento:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --dry-run
```

Ver o estado e os logs:

```sh
sudo systemctl status moodle-cron-scheduler.service
sudo journalctl -u moodle-cron-scheduler.service --since '1 hour ago'
```

## 10. MariaDB

Verificar o healthcheck:

```sh
docker inspect --format '{{.State.Health.Status}}' moodle_db
```

Abrir o cliente como root, solicitando a senha de forma interativa:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -p
```

Dentro do MariaDB, comandos uteis:

```sql
SHOW DATABASES;
SHOW PROCESSLIST;
SELECT USER(), VERSION();
EXIT;
```

Testar o banco usando as credenciais ja presentes dentro do container, sem
mostrar a senha no host:

```sh
docker exec moodle_db sh -c 'mariadb-admin ping -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD"'
```

## 11. Redis e proxy Caddy

Testar o Redis:

```sh
docker exec moodle_redis redis-cli ping
docker exec moodle_redis redis-cli dbsize
docker exec moodle_redis redis-cli info memory
```

Nao use `redis-cli FLUSHALL`: todas as instituicoes compartilham o Redis e esse
comando apaga as chaves de todas elas.

Validar a configuracao do Caddy:

```sh
docker compose -f docker-compose.infra.yml exec proxy caddy validate --config /etc/caddy/Caddyfile
```

Recarregar o Caddy depois de alterar `proxy/Caddyfile.local`, sem reiniciar o
container:

```sh
docker compose -f docker-compose.infra.yml exec proxy caddy reload --config /etc/caddy/Caddyfile
```

Testar a rota atual:

```sh
curl -I http://localhost:8088/i/escola-modelo/
```

## 12. Criar uma nova instituicao

O antigo `scripts/provision-institution.py` foi removido. Siga
`docs/criar-instancia-manual-moodle.md`.

Ao declarar o servico no Compose, inclua obrigatoriamente:

```yaml
labels:
  com.w3soft.moodle.role: tenant
```

Depois de subir a instituicao, confirme que o scheduler a encontrou:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --discover
sudo /usr/local/sbin/moodle-cron-scheduler --dry-run
```

## 13. Volumes e persistencia

Inspecionar os volumes principais:

```sh
docker volume inspect moodle_db_data
docker volume inspect moodle_redis_data
docker volume inspect moodledata_escola_modelo
```

Descobrir quais volumes um container usa:

```sh
docker inspect --format '{{range .Mounts}}{{println .Name "->" .Destination}}{{end}}' moodle_escola_modelo
```

Criar antecipadamente o volume externo de uma instituicao:

```sh
docker volume create moodledata_escola_exemplo
```

Dados importantes:

```text
moodle_db_data               -> todos os bancos das instituicoes
moodle_redis_data            -> persistencia do Redis
moodle_caddy_data/config     -> estado do Caddy
moodledata_<instituicao>     -> arquivos enviados, caches e dados da instituicao
```

Remover ou recriar um container nao apaga automaticamente esses volumes.

## 14. Backup

Um backup Moodle completo precisa conter, no minimo:

1. dump do banco da instituicao;
2. conteudo do volume `moodledata` da mesma instituicao;
3. arquivo `secrets/<instituicao>.local.env`, guardado em local seguro;
4. codigo/tag exata da imagem usada.

Crie uma pasta local ignorada pelo Git:

```sh
mkdir -p backups
```

Ative manutencao para evitar mudancas durante o backup:

```sh
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/maintenance.php --enable
```

Pare temporariamente o scheduler, aguarde qualquer cron ativo terminar e pare o
tenant para obter a copia mais consistente:

```sh
sudo systemctl stop moodle-cron-scheduler.service
docker compose -f docker-compose.instituicoes.yml stop moodle_escola_modelo
```

Descubra o nome correto do banco sem imprimir a senha:

```sh
sed -n 's/^MOODLE_DB_NAME=//p' secrets/escola-modelo.local.env
```

Substitua `NOME_DO_BANCO` no dump:

```sh
docker exec moodle_db sh -c 'mariadb-dump --single-transaction --quick --routines --triggers --events -uroot -p"$MARIADB_ROOT_PASSWORD" NOME_DO_BANCO' > backups/NOME_DO_BANCO.sql
```

Compacte o `moodledata` com um container temporario, mantendo o tenant parado:

```sh
docker compose -f docker-compose.instituicoes.yml run --rm --no-deps -T moodle_escola_modelo sh -c 'tar -C /var/www/moodledata -czf - .' > backups/moodledata_escola_modelo.tgz
```

Suba o tenant, desative a manutencao e reative o agendamento do cron:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_modelo
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/maintenance.php --disable
sudo systemctl start moodle-cron-scheduler.service
```

Confira os arquivos sem mostrar seu conteudo:

```sh
ls -lh backups/
shasum -a 256 backups/*
# Em Linux, se shasum nao estiver disponivel:
sha256sum backups/*
```

> A pasta `backups/`, dumps e secrets nao devem ser enviados ao Git. Copie os
> backups para outro armazenamento seguro e teste a restauracao periodicamente.

## 15. Restauracao

Restaurar sobrescrevendo um ambiente existente e destrutivo. Antes de comecar:

- mantenha uma copia dos dados atuais;
- confirme banco, tenant e volume de destino;
- pare o tenant;
- prefira restaurar primeiro em um banco e volume novos;
- restaure banco e `moodledata` obtidos no mesmo backup.

Parar somente a instituicao:

```sh
docker compose -f docker-compose.instituicoes.yml stop moodle_escola_modelo
```

Restaurar um dump em um banco vazio ja criado:

```sh
docker exec -i moodle_db sh -c 'mariadb --ssl=0 -uroot -p"$MARIADB_ROOT_PASSWORD" NOME_DO_BANCO' < backups/NOME_DO_BANCO.sql
```

Restaurar `moodledata` em um volume vazio usando um container temporario do
proprio servico:

```sh
docker compose -f docker-compose.instituicoes.yml run --rm --no-deps -T moodle_escola_modelo sh -c 'tar -xzf - -C /var/www/moodledata' < backups/moodledata_escola_modelo.tgz
```

Subir, limpar caches e conferir os logs:

```sh
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_modelo
docker exec -u www-data moodle_escola_modelo php /var/www/html/admin/cli/purge_caches.php
docker logs --tail=200 moodle_escola_modelo
```

Se o backup veio de outra URL, ajuste `MOODLE_URL` no secret e recrie o
container. Migracoes que tambem exigem substituicao de URLs no banco devem usar
as ferramentas CLI oficiais do Moodle e ser testadas antes em uma copia.

## 16. Atualizacao das imagens

Baixar novas versoes das imagens prontas da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml pull
```

Aplicar as imagens baixadas:

```sh
docker compose -f docker-compose.infra.yml up -d
```

A imagem Moodle e construida localmente a partir de `moodle/Dockerfile`:

```sh
docker build --pull -t w3soft/moodle:2026.07.1-local ./moodle
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

Antes de atualizar Moodle ou MariaDB em producao, faca backup completo e leia as
notas de compatibilidade da versao. Nao use `latest` no lugar das versoes
fixadas sem testar.

## 17. Limpeza segura e comandos destrutivos

Remover somente containers parados nao usados:

```sh
docker container prune
```

Remover somente imagens sem referencia:

```sh
docker image prune
```

Esses comandos pedem confirmacao. Confira antes com:

```sh
docker ps -a
docker image ls
docker system df
```

### Zona de perigo

Os comandos abaixo apagam dados. Eles sao documentados para que voce os
reconheca, nao para uso rotineiro.

Apagar o modo simples, incluindo banco e `moodledata`:

```sh
docker compose -f docker-compose.yml down -v
```

Apagar os volumes da infraestrutura multi-instituicao, incluindo todos os
bancos. As instituicoes devem ter sido derrubadas primeiro:

```sh
docker compose -f docker-compose.instituicoes.yml down
docker compose -f docker-compose.infra.yml down -v
```

Apagar definitivamente o `moodledata` de uma instituicao, depois de parar e
remover seu container:

```sh
docker volume rm moodledata_escola_modelo
```

Outros comandos de alto risco:

```sh
docker volume prune
docker system prune --volumes
```

> Nunca execute limpeza de volumes sem backup verificado. O volume
> `moodle_db_data` contem os bancos de todas as instituicoes, enquanto cada
> `moodledata_*` contem os arquivos da instituicao correspondente.

## 18. Sequencias recomendadas

### Comecar o trabalho no modo multi-instituicao

```sh
docker compose -f docker-compose.infra.yml config --quiet
docker compose -f docker-compose.instituicoes.yml config --quiet
docker compose -f docker-compose.infra.yml up -d
docker compose -f docker-compose.instituicoes.yml up -d
docker compose -f docker-compose.infra.yml ps
docker compose -f docker-compose.instituicoes.yml ps
```

### Alterar um secret de uma instituicao

```sh
# Edite secrets/escola-modelo.local.env
docker compose -f docker-compose.instituicoes.yml config --quiet
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_modelo
docker logs --tail=200 moodle_escola_modelo
```

### Alterar codigo/configuracao da imagem Moodle

```sh
docker build -t w3soft/moodle:2026.07.1-local ./moodle
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
docker compose -f docker-compose.instituicoes.yml logs --tail=200
```

### Encerrar o ambiente preservando dados

```sh
docker compose -f docker-compose.instituicoes.yml down
docker compose -f docker-compose.infra.yml down
```

## 19. Regra pratica para nao se perder

Antes de confirmar qualquer comando, identifique:

```text
1. Qual modo estou usando: simples ou multi-instituicao?
2. Qual arquivo Compose devo passar em -f?
3. Estou referenciando um servico Compose ou um nome de container?
4. O comando apenas consulta, reinicia/recria ou apaga algo?
5. Se ele altera banco ou volume, meu backup foi testado?
```

Na duvida, comece por comandos somente de leitura:

```sh
docker compose -f ARQUIVO.yml config --quiet
docker compose -f ARQUIVO.yml ps
docker ps -a
docker logs --tail=100 NOME_DO_CONTAINER
docker inspect NOME_DO_CONTAINER
docker system df
```
