# Subir o projeto Moodle no servidor

Este guia mostra o passo a passo operacional para subir os containers do projeto depois que os arquivos ja estiverem no local correto do servidor.

O projeto possui dois modos principais:

- `docker-compose.yml`: stack simples/local, com um Moodle e um banco.
- `docker-compose.infra.yml` + `docker-compose.instituicoes.yml`: stack multi-instituicao, com infraestrutura compartilhada e um Moodle por instituicao.

Para servidor, use preferencialmente o modo multi-instituicao.

## 1. Entrar na pasta do projeto

Substitua o caminho abaixo pelo caminho real do servidor:

```sh
cd /caminho/do/projeto/moodle-docker
```

Confirme que os arquivos principais existem:

```sh
ls
```

Voce deve ver, no minimo:

```text
docker-compose.yml
docker-compose.infra.yml
docker-compose.instituicoes.yml
moodle
proxy
secrets
scripts
config
```

## 2. Verificar Docker e Docker Compose

```sh
docker compose version
docker ps
```

Se esses comandos falharem, corrija a instalacao/permissao do Docker antes de continuar.

## 3. Revisar arquivos de ambiente

Antes de subir em producao, revise os arquivos em:

```text
secrets/
```

Pontos importantes:

- senhas do banco;
- senhas dos administradores Moodle;
- `MOODLE_URL`;
- dominio publico;
- variaveis que ainda estejam com valor `local`;
- nomes das instituicoes que realmente devem subir.

Para impedir a exposicao da pagina inicial e de dados de cursos a visitantes,
inclua (ou mantenha) esta configuracao no arquivo de ambiente de cada
instituicao:

```text
MOODLE_FORCE_LOGIN=1
```

Com ela ativa, o Moodle redireciona acessos deslogados da URL base da
instituicao para `login/index.php`.

Exemplos de arquivos esperados:

```text
secrets/infra.local.env
secrets/escola-a.local.env
secrets/escola-b.local.env
```

## 4. Ajustar portas do proxy para producao, se necessario

No arquivo `docker-compose.infra.yml`, o proxy esta configurado para portas locais:

```yaml
ports:
  - "8088:80"
  - "8443:443"
```

Para producao com dominio real, normalmente use:

```yaml
ports:
  - "80:80"
  - "443:443"
```

Depois, revise tambem:

```text
proxy/Caddyfile.local
```

Se o servidor for acessado somente por IP ou por uma porta especifica, mantenha as portas atuais e acesse usando `http://IP_DO_SERVIDOR:8088`.

## 5. Validar os arquivos Compose

```sh
docker compose -f docker-compose.infra.yml config
```

```sh
docker compose -f docker-compose.instituicoes.yml config
```

Se algum comando mostrar erro, corrija o arquivo indicado antes de continuar.

## 6. Construir a imagem Moodle

A stack das instituicoes usa a imagem:

```text
w3soft/moodle:2026.07.1-local
```

Construa essa imagem no servidor:

```sh
docker compose -f docker-compose.yml build moodle
```

## 7. Subir a infraestrutura compartilhada

```sh
docker compose -f docker-compose.infra.yml up -d
```

Esse comando sobe:

```text
moodle_db
moodle_redis
moodle_proxy
```

## 8. Conferir a infraestrutura

```sh
docker compose -f docker-compose.infra.yml ps
```

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Teste o Redis:

```sh
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

Teste o MariaDB:

```sh
docker exec moodle_db mariadb --version
```

## 9. Criar bancos e usuarios das instituicoes

Antes de subir os Moodles das instituicoes, os bancos e usuarios precisam existir no MariaDB.

Entre no MariaDB como root:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -p
```

Dentro do prompt do MariaDB, crie os bancos e usuarios conforme as instituicoes configuradas em `docker-compose.instituicoes.yml` e `secrets/*.env`.

Exemplo para `escola-a`:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

GRANT ALL PRIVILEGES ON moodle_escola_a.*
  TO 'moodle_escola_a'@'%';

FLUSH PRIVILEGES;
```

Repita o processo para cada escola usando o banco, usuario e senha definidos no respectivo arquivo `secrets/NOME.local.env`.

Para sair:

```sql
exit;
```

## 10. Subir os containers Moodle das instituicoes

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

## 11. Conferir os containers das instituicoes

```sh
docker compose -f docker-compose.instituicoes.yml ps
```

```sh
docker ps --filter "name=moodle_escola"
```

Para ver logs de uma instituicao especifica:

```sh
docker logs --tail=120 moodle_escola_a
```

Para acompanhar em tempo real:

```sh
docker logs -f moodle_escola_a
```

## 12. Testar acesso pelo navegador

Com as portas locais atuais:

```text
http://IP_DO_SERVIDOR:8088
http://IP_DO_SERVIDOR:8088/i/escola-a/
http://IP_DO_SERVIDOR:8088/i/escola-b/
```

Com portas de producao `80` e `443`:

```text
http://SEU_DOMINIO
https://SEU_DOMINIO
https://SEU_DOMINIO/i/escola-a/
https://SEU_DOMINIO/i/escola-b/
```

## 13. Testar cron do Moodle manualmente

Execute o cron de uma instituicao:

```sh
docker exec -u www-data moodle_escola_a php /var/www/html/admin/cli/cron.php
```

Se necessario, veja os logs:

```sh
docker logs --tail=120 moodle_escola_a
```

## 14. Preparar cron centralizado

Crie a pasta de logs:

```sh
mkdir -p logs/moodle-cron
```

Garanta permissao de execucao nos scripts:

```sh
chmod +x scripts/run-moodle-crons.sh scripts/run-moodle-crons-distributed.sh
```

Confira se as instituicoes estao listadas em:

```text
config/moodle-cron-tenants.txt
```

Teste o distribuidor de cron:

```sh
./scripts/run-moodle-crons-distributed.sh
```

Confira os logs:

```sh
tail -n 80 logs/moodle-cron/distributor.log
```

## 15. Agendar o cron no servidor

Abra o crontab:

```sh
crontab -e
```

Adicione a linha abaixo, ajustando o caminho do projeto:

```cron
* * * * * cd /caminho/do/projeto/moodle-docker && ./scripts/run-moodle-crons-distributed.sh
```

Salve e confira:

```sh
crontab -l
```

Apos alguns minutos, verifique:

```sh
tail -n 80 logs/moodle-cron/distributor.log
```

## 16. Comandos uteis de operacao

Ver containers:

```sh
docker ps
```

Ver uso de recursos:

```sh
docker stats
```

Ver logs da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml logs --tail=100
```

Ver logs das instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml logs --tail=100
```

Reiniciar infraestrutura:

```sh
docker compose -f docker-compose.infra.yml restart
```

Reiniciar instituicoes:

```sh
docker compose -f docker-compose.instituicoes.yml restart
```

Parar instituicoes sem apagar dados:

```sh
docker compose -f docker-compose.instituicoes.yml stop
```

Parar infraestrutura sem apagar dados:

```sh
docker compose -f docker-compose.infra.yml stop
```

Subir tudo novamente:

```sh
docker compose -f docker-compose.infra.yml up -d
docker compose -f docker-compose.instituicoes.yml up -d
```

Recriar containers das instituicoes apos alteracao de configuracao:

```sh
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate
```

## 17. Checklist final

- Docker e Docker Compose funcionando.
- Arquivos `secrets/*.env` revisados.
- Portas do proxy ajustadas para o ambiente.
- `docker compose -f docker-compose.infra.yml config` sem erro.
- `docker compose -f docker-compose.instituicoes.yml config` sem erro.
- Imagem Moodle construida.
- Infraestrutura em execucao.
- Redis respondendo `PONG`.
- Bancos e usuarios das instituicoes criados.
- Containers Moodle das instituicoes em execucao.
- Acesso HTTP/HTTPS testado.
- Cron manual testado.
- Cron centralizado configurado no `crontab`.
