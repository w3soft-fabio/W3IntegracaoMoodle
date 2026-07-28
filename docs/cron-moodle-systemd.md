# Cron centralizado do Moodle com systemd

## Objetivo

O host Linux executa o `admin/cli/cron.php` de todos os containers Moodle de
instituicao. Nao existe container exclusivo para cron e nao existe lista manual
de tenants.

O servico:

- redescobre os containers ativos no inicio de cada minuto;
- considera somente containers com o label
  `com.w3soft.moodle.role=tenant`;
- ordena os nomes para produzir um balanceamento deterministico;
- usa as janelas de 0, 15, 30 e 45 segundos;
- limita a quantidade global de execucoes simultaneas;
- impede sobreposicao por tenant com `flock`;
- grava descoberta, inicio, fim, duracao, falhas e skips no journal.

## Arquivos

| Arquivo no projeto | Destino no servidor |
|---|---|
| `scripts/moodle-cron-scheduler.sh` | `/usr/local/sbin/moodle-cron-scheduler` |
| `systemd/moodle-cron-scheduler.service` | `/etc/systemd/system/moodle-cron-scheduler.service` |
| `config/moodle-cron-scheduler.env.example` | `/etc/default/moodle-cron-scheduler` |

## Como o balanceamento funciona

Com quatro ou mais tenants, a lista ordenada e distribuida em round-robin pelas
quatro janelas. A diferenca de tamanho entre os grupos e de no maximo um.

Com menos tenants:

| Quantidade | Janelas |
|---:|---|
| 1 | 0s |
| 2 | 0s e 30s |
| 3 | 0s, 15s e 30s |
| 4 | 0s, 15s, 30s e 45s |

O balanceamento e recalculado a cada minuto. Se um container parar, iniciar ou
for removido, o proximo ciclo refletira a mudanca.

## Concorrencia e locks

`MOODLE_CRON_MAX_PARALLEL` limita quantos comandos `cron.php` podem rodar ao
mesmo tempo no servidor. O padrao recomendado inicial e `2`.

Cada tenant tambem tem um lock proprio. Se sua execucao anterior ainda estiver
ativa, a nova chamada e ignorada com
`reason=previous_execution_running`. O lock usa `flock` e e liberado pelo
kernel quando o processo termina, inclusive em encerramentos inesperados.

Um worker pode aguardar capacidade ate
`MOODLE_CRON_QUEUE_TIMEOUT_SECONDS`. Depois disso, ele registra
`reason=capacity_timeout` e tenta novamente no ciclo seguinte.

## Preparacao do Compose

Todo servico de instituicao deve possuir:

```yaml
labels:
  com.w3soft.moodle.role: tenant
```

Proxy, banco, Redis e outros servicos auxiliares nao devem receber esse label.
O arquivo `docker-compose.instituicoes.yml` deste projeto ja aplica o label ao
tenant modelo.

Depois de atualizar o projeto no servidor, recrie os containers das
instituicoes para aplicar o label:

```sh
cd /opt/moodle-docker
docker compose -f docker-compose.instituicoes.yml up -d
```

Confirme o label:

```sh
docker inspect \
  --format '{{ index .Config.Labels "com.w3soft.moodle.role" }}' \
  moodle_escola_modelo
```

A saida esperada e `tenant`.

## Remocao dos agendadores antigos

Antes de ativar o novo servico, procure mecanismos antigos:

```sh
docker ps -a --format '{{.Names}}' | sort | grep '_cron$' || true
sudo systemctl list-unit-files | grep -E 'moodle.*cron|cron.*moodle' || true
sudo crontab -l || true
crontab -l || true
```

Revise a lista e remova somente containers acompanhantes terminados em `_cron`.
Use nomes exatos, por exemplo:

```sh
docker rm -f moodle_escola_modelo_cron
```

Remova do `crontab` qualquer chamada para
`run-moodle-crons-distributed.sh`, `run-moodle-crons.sh` ou para
`admin/cli/cron.php`. Nao mantenha dois agendadores ativos.

## Instalacao

Confirme os binarios necessarios:

```sh
command -v bash docker flock awk sort
```

Em Debian/Ubuntu, `flock` pertence ao pacote `util-linux`, normalmente ja
instalado. Se `MOODLE_CRON_COMMAND_TIMEOUT_SECONDS` for maior que zero, o
comando `timeout` do pacote `coreutils` tambem deve estar disponivel.

Instale o scheduler, sua configuracao e a unidade:

```sh
cd /opt/moodle-docker
sudo install -o root -g root -m 0750 \
  scripts/moodle-cron-scheduler.sh \
  /usr/local/sbin/moodle-cron-scheduler
sudo install -o root -g root -m 0644 \
  config/moodle-cron-scheduler.env.example \
  /etc/default/moodle-cron-scheduler
sudo install -o root -g root -m 0644 \
  systemd/moodle-cron-scheduler.service \
  /etc/systemd/system/moodle-cron-scheduler.service
```

Valide a unidade:

```sh
sudo systemd-analyze verify /etc/systemd/system/moodle-cron-scheduler.service
```

## Validacao antes de ativar

Confira a descoberta:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --discover
```

A saida deve conter somente containers de instituicoes. Em seguida, confira o
balanceamento sem executar PHP:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --dry-run
```

Para executar um unico ciclo real, iniciando no proximo minuto:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --once
```

Nao execute `--once` enquanto o servico permanente estiver ativo; o lock global
recusara a segunda instancia.

## Ativacao

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now moodle-cron-scheduler.service
sudo systemctl status moodle-cron-scheduler.service
```

Acompanhe os eventos:

```sh
sudo journalctl -u moodle-cron-scheduler.service -f
```

Consultar as ultimas duas horas:

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since '2 hours ago' \
  --no-pager
```

Consultar um tenant:

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since today \
  --no-pager |
  grep 'tenant=moodle_escola_modelo'
```

## Configuracao

Edite `/etc/default/moodle-cron-scheduler` e reinicie o servico depois de
qualquer alteracao:

```sh
sudo systemctl restart moodle-cron-scheduler.service
```

Variaveis disponiveis:

| Variavel | Padrao | Funcao |
|---|---:|---|
| `MOODLE_CRON_DISCOVERY_MODE` | `label` | Descoberta por `label` ou, temporariamente, por `name`. |
| `MOODLE_CRON_TENANT_LABEL` | `com.w3soft.moodle.role=tenant` | Label exigido no modo `label`. |
| `MOODLE_CRON_MAX_PARALLEL` | `2` | Maximo global de execucoes simultaneas. |
| `MOODLE_CRON_QUEUE_TIMEOUT_SECONDS` | `50` | Espera maxima por capacidade. |
| `MOODLE_CRON_COMMAND_TIMEOUT_SECONDS` | `0` | Limite do comando; zero nao interrompe. |
| `MOODLE_CRON_SLOW_WARNING_SECONDS` | `60` | Duracao que gera aviso. |

O modo `name` existe somente para transicao. Ele aceita nomes iniciados por
`moodle_`, exclui exatamente `moodle_proxy`, `moodle_redis`, `moodle_db` e
nomes terminados em `_cron`.

## Testes operacionais

### Entrada e saida dinamica

Pare um tenant:

```sh
docker stop moodle_escola_modelo
```

No minuto seguinte, o log de descoberta deve mostrar uma instituicao a menos.
Suba novamente:

```sh
docker start moodle_escola_modelo
```

Ele deve reaparecer no proximo ciclo.

### Sobreposicao

Se um cron durar mais de um minuto, procure:

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since '10 minutes ago' \
  --no-pager |
  grep 'reason=previous_execution_running'
```

Isso confirma que o segundo processo nao foi iniciado.

### Falhas

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since today \
  --no-pager |
  grep -E 'level=error|result=failure|reason=capacity_timeout'
```

Falhas frequentes por capacidade indicam que
`MOODLE_CRON_MAX_PARALLEL`, os recursos do servidor ou a quantidade de trabalho
do Moodle precisam ser revistos.

## Atualizacao

Depois de atualizar o repositorio:

```sh
cd /opt/moodle-docker
sudo install -o root -g root -m 0750 \
  scripts/moodle-cron-scheduler.sh \
  /usr/local/sbin/moodle-cron-scheduler
sudo install -o root -g root -m 0644 \
  systemd/moodle-cron-scheduler.service \
  /etc/systemd/system/moodle-cron-scheduler.service
sudo systemctl daemon-reload
sudo systemctl restart moodle-cron-scheduler.service
sudo systemctl status moodle-cron-scheduler.service
```

O arquivo `/etc/default/moodle-cron-scheduler` nao e sobrescrito nessa
sequencia.

## Rollback

Para interromper o scheduler do host:

```sh
sudo systemctl disable --now moodle-cron-scheduler.service
```

Reative um mecanismo antigo somente depois de confirmar que o servico ficou
inativo:

```sh
sudo systemctl is-active moodle-cron-scheduler.service
```
