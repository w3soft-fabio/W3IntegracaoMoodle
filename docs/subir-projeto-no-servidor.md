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

Defina tambem o idioma inicial do Moodle para portugues do Brasil:

```text
MOODLE_DEFAULT_LANG=pt_br
MOODLE_AUTO_DETECT_LANG=0
```

O bootstrap persiste esse idioma como padrao global da instituicao e, com a
autodeteccao desabilitada, a preferencia de idioma do navegador nao troca a
tela publica para ingles. A preferencia individual de idioma de um usuario
autenticado continua sendo respeitada.

Os volumes `moodledata_*` sao externos ao Compose para que os dados das
instituicoes nao dependam do nome do projeto Compose. Antes de subir uma nova
instituicao manualmente, crie o volume correspondente uma unica vez:

```sh
docker volume create moodledata_nome_da_instituicao
```

### Migrar containers de um nome de projeto Compose antigo

Se os containers existentes foram criados com outro nome de projeto (por
exemplo, `w3integracaomoodle`), remova **somente os containers** antigos antes
de executar o `up` sem `-p`. Este comando preserva os volumes, pois nao usa
`-v`:

```sh
docker compose -p w3integracaomoodle \
  -f docker-compose.instituicoes.yml down
```

Depois, o comando padrao passa a recriar os containers usando a imagem atual e
os mesmos volumes de dados. O arquivo fixa o novo nome de projeto como
`moodle-docker`, portanto nao e necessario informar `-p`:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
```

Nunca use `down -v` nessa migracao: essa opcao remove os volumes e, com eles,
os arquivos enviados e demais dados persistidos pelo Moodle.

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

Todos os containers de instituicao precisam do label:

```yaml
labels:
  com.w3soft.moodle.role: tenant
```

Recrie os tenants para aplicar o label e confira a descoberta:

```sh
docker compose -f docker-compose.instituicoes.yml up -d
sudo ./scripts/moodle-cron-scheduler.sh --discover
```

Instale os arquivos do servico:

```sh
sudo install -o root -g root -m 0750 scripts/moodle-cron-scheduler.sh /usr/local/sbin/moodle-cron-scheduler
sudo install -o root -g root -m 0644 config/moodle-cron-scheduler.env.example /etc/default/moodle-cron-scheduler
sudo install -o root -g root -m 0644 systemd/moodle-cron-scheduler.service /etc/systemd/system/moodle-cron-scheduler.service
```

Confira o balanceamento sem executar PHP:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --dry-run
```

## 15. Ativar o cron no servidor

Nao adicione uma entrada no `crontab`. Ative o servico permanente:

```sh
sudo systemd-analyze verify /etc/systemd/system/moodle-cron-scheduler.service
sudo systemctl daemon-reload
sudo systemctl enable --now moodle-cron-scheduler.service
sudo systemctl status moodle-cron-scheduler.service
```

Confira os eventos:

```sh
sudo journalctl -u moodle-cron-scheduler.service -f
```

O procedimento completo, incluindo remocao de agendadores antigos e rollback,
esta em `docs/cron-moodle-systemd.md`.

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
- Cron centralizado configurado no `systemd`.
