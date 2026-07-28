# Entendendo o cron do Moodle e o serviço centralizado no servidor

Este documento explica por que o cron é necessário para o Moodle e como este projeto o executa em um servidor Linux. Ele complementa [cron-moodle-systemd.md](cron-moodle-systemd.md), que contém o roteiro operacional resumido.

Os exemplos consideram o projeto instalado em:

```text
/home/projetos/moodle-docker
```

O texto foi escrito para quem conhece C#, mas ainda não trabalha diariamente com Linux, Docker ou `systemd`.

## 1. Por que o Moodle precisa de cron

Uma requisição normal do Moodle acontece quando alguém abre uma página: o servidor recebe a requisição HTTP, gera a resposta e encerra aquele trabalho. Porém, várias responsabilidades não pertencem a uma página ou usuário específico.

Exemplos de trabalho em segundo plano do Moodle:

- enviar e-mails pendentes, como avisos de fórum, notas e senhas;
- executar tarefas agendadas dos plugins;
- processar filas internas;
- limpar sessões, caches e dados temporários expirados;
- atualizar dados que dependem de processamento posterior;
- executar manutenções e integrações do Moodle.

Essas atividades são iniciadas pelo comando:

```sh
php /var/www/html/admin/cli/cron.php --keep-alive=0
```

Como o Moodle roda dentro de um container Docker, o host executa o comando dentro do container correto:

```sh
docker exec -u www-data NOME_DO_CONTAINER \
  php /var/www/html/admin/cli/cron.php --keep-alive=0
```

`www-data` é o usuário usado pelo Apache/PHP no container. Executar como esse usuário evita que arquivos gerados pelo cron pertençam ao `root` e se tornem inacessíveis para a aplicação web.

### Analogia com C#

Imagine uma aplicação ASP.NET que precisa enviar e-mails pendentes. Fazer isso dentro de cada `GET /` deixaria páginas lentas e faria o envio parar quando não houvesse acessos. O desenho adequado seria um `BackgroundService` ou uma fila com worker.

O cron do Moodle tem esse mesmo papel: ele é o gatilho de um trabalhador em segundo plano fornecido pelo próprio Moodle. A diferença é que o Moodle o oferece como um comando PHP, que precisa ser disparado pelo sistema operacional.

```text
Navegador                         Trabalho em segundo plano
---------                         -------------------------
Usuário abre uma página           systemd chama cron.php
        |                                     |
        v                                     v
Apache/PHP responde               Moodle processa tarefas pendentes
```

Sem cron, o Moodle pode continuar abrindo no navegador, mas tarefas pendentes passam a atrasar ou falhar.

## 2. Por que chamar a cada minuto

O cron do Moodle deve ser chamado regularmente, normalmente a cada minuto. Isso não quer dizer que todas as tarefas do Moodle rodam uma vez por minuto: o Moodle verifica o que está vencido e controla suas próprias tarefas internas.

Chamar com frequência reduz atrasos, distribui manutenção no tempo e torna falhas visíveis rapidamente. Em um ambiente multi-instituição, cada container Moodle tem configuração, banco e tarefas próprias. Portanto, cada instituição precisa receber sua chamada de `cron.php`.

## 3. A decisão de arquitetura

Uma abordagem anterior criava um segundo container por instituição, com sufixo `_cron`. Ele montava o mesmo `moodledata`, executava o cron, esperava sessenta segundos e repetia.

```text
moodle_colegio_modelo       aplicação web
moodle_colegio_modelo_cron  somente para chamar cron.php
```

Funciona, mas cria um container adicional por escola. A implementação atual mantém essa responsabilidade no host Linux, usando um único serviço leve:

```text
Servidor Linux
│
├── systemd
│   └── moodle-cron-scheduler.service
│       └── moodle-cron-scheduler
│
├── Docker
│   ├── moodle_colegio_modelo
│   ├── moodle_colegio_monsenhor_adelmar_da_mota_valenca
│   ├── moodle_proxy
│   ├── moodle_redis
│   └── moodle_db
│
└── O scheduler executa cron.php apenas nos tenants Moodle.
```

Assim, os containers Moodle continuam responsáveis pela aplicação e o host apenas organiza quando cada cron deve iniciar.

## 4. Componentes implementados

| Componente | Local | Responsabilidade | Analogia em C# |
|---|---|---|---|
| Scheduler | `scripts/moodle-cron-scheduler.sh` | Descoberta, distribuição, locks e execução. | `BackgroundService`. |
| Serviço | `systemd/moodle-cron-scheduler.service` | Início no boot, reinício e logs. | Host de um worker. |
| Configuração | `config/moodle-cron-scheduler.env.example` | Limites e comportamento operacional. | `appsettings.Production.json`. |
| Label Docker | `com.w3soft.moodle.role=tenant` | Marca os containers que são instituições. | Campo `IsTenantMoodle`. |
| `flock` | `/run/moodle-cron-scheduler` | Exclusão mútua entre processos. | `lock`, `Mutex` ou `SemaphoreSlim`. |
| Journal | `journalctl` | Retenção e consulta de logs. | Provider centralizado de logging. |

## 5. Como uma instituição é identificada

O scheduler não usa uma lista manual. Uma lista precisa ser alterada toda vez que uma escola entra ou sai, e alguém pode esquecer de atualizá-la.

Cada serviço Moodle de instituição recebe este label no Compose:

```yaml
labels:
  com.w3soft.moodle.role: tenant
```

O scheduler pede ao Docker os containers em execução com esse label. Assim, os tenants são escolhidos por intenção:

```text
moodle_colegio_modelo
moodle_colegio_monsenhor_adelmar_da_mota_valenca
```

Proxy, Redis e banco não possuem o label e ficam de fora:

```text
moodle_proxy
moodle_redis
moodle_db
```

Isso é mais seguro que filtrar apenas nomes iniciados por `moodle_`. Um container futuro chamado `moodle_backup` poderia ter o mesmo prefixo, mas não deveria executar `cron.php`.

## 6. O ciclo executado a cada minuto

No início de cada minuto, o scheduler faz o seguinte:

```text
1. Consulta Docker pelos containers com label de tenant
2. Ordena os nomes para manter planejamento previsível
3. Calcula a janela de início de cada tenant
4. Inicia workers em 0s, 15s, 30s e 45s
5. Cada worker obtém capacidade e lock individual
6. O worker executa docker exec -u www-data ... cron.php
7. Início, fim, duração e erros são escritos no journal
8. No minuto seguinte, todo o planejamento é refeito
```

Essa redescoberta periódica trata entrada e retirada de containers. Uma nova instituição entra no planejamento no próximo minuto; uma instituição parada ou removida deixa de participar.

## 7. Distribuição nas quatro janelas

Executar todos os crons no segundo zero criaria um pico de CPU, memória, disco, MariaDB e Redis. Por isso, o minuto é dividido em quatro janelas:

```text
00s ── grupo 1
15s ── grupo 2
30s ── grupo 3
45s ── grupo 4
```

Com oito tenants, por exemplo:

| Janela | Tenants iniciados |
|---|---|
| 0s | 1 e 5 |
| 15s | 2 e 6 |
| 30s | 3 e 7 |
| 45s | 4 e 8 |

Com menos de quatro tenants, o scheduler também os espalha:

| Quantidade | Horários de início |
|---:|---|
| 1 | 0s |
| 2 | 0s e 30s |
| 3 | 0s, 15s e 30s |
| 4 ou mais | utiliza as quatro janelas |

## 8. Concorrência: por que quatro janelas não bastam

As janelas controlam quando os trabalhos começam, mas não garantem sozinhas quantos processos estarão ativos. Se houver vinte tenants, cinco podem cair na mesma janela.

`MOODLE_CRON_MAX_PARALLEL=2` limita o host a duas execuções de `cron.php` ao mesmo tempo, mesmo que existam várias instituições prontas.

Em C#, é semelhante a um `SemaphoreSlim(2)`:

```csharp
await semaphore.WaitAsync(cancellationToken);
try
{
    await RunMoodleCronAsync(tenant);
}
finally
{
    semaphore.Release();
}
```

No shell, o scheduler usa locks de capacidade. Um worker obtém uma das vagas antes de iniciar o `docker exec`; quando termina, a vaga é liberada.

Se não houver vaga dentro de cinquenta segundos, que é o valor inicial de `MOODLE_CRON_QUEUE_TIMEOUT_SECONDS`, o worker registra `reason=capacity_timeout` e tenta novamente no próximo minuto. Isso evita uma fila infinita e mostra claramente a sobrecarga nos logs.

## 9. Locks por instituição: como se evita duplicidade

Um cron pode durar mais de um minuto. Iniciar outro processo para a mesma instituição enquanto o anterior ainda está ativo gera concorrência desnecessária sobre a aplicação e o banco.

Cada tenant possui um lock separado, por exemplo:

```text
/run/moodle-cron-scheduler/tenant-moodle_colegio_modelo.lock
```

O primeiro worker obtém o lock e executa. O segundo registra `reason=previous_execution_running` e encerra sem iniciar uma execução duplicada.

É equivalente ao seguinte padrão conceitual em C#:

```csharp
if (!tenantLocks.TryAdd(tenantName, true))
{
    logger.LogWarning("Cron anterior ainda está executando para {Tenant}", tenantName);
    return;
}

try
{
    await RunMoodleCronAsync(tenantName);
}
finally
{
    tenantLocks.TryRemove(tenantName, out _);
}
```

O mecanismo real usa `flock`, que é mais seguro que criar um diretório comum como lock: o kernel libera o lock quando o processo termina, inclusive se for interrompido inesperadamente.

## 10. Papel do systemd

`systemd` é o gerenciador de serviços da maioria das distribuições Linux. Ele inicia programas no boot, acompanha se continuam vivos, reinicia processos que falham e disponibiliza logs.

No Windows, a comparação mais próxima é combinar um Windows Service com o Service Control Manager. Em uma aplicação .NET, seria semelhante a registrar um worker em `IHostedService` e deixar o host mantê-lo ativo.

A unidade deste projeto fica em:

```text
/etc/systemd/system/moodle-cron-scheduler.service
```

| Diretiva | Efeito |
|---|---|
| `ExecStart` | Inicia `/usr/local/sbin/moodle-cron-scheduler --daemon`. |
| `After=docker.service` | Espera o Docker iniciar antes do scheduler. |
| `Restart=always` | Reinicia o scheduler se ele encerrar por falha. |
| `RuntimeDirectory` | Cria os locks temporários em `/run`. |
| `KillMode=control-group` | Ao parar o serviço, encerra scheduler e workers filhos. |
| `EnvironmentFile` | Carrega configuração sem editar a unidade. |
| `ProtectSystem` e `ProtectHome` | Restringem acessos desnecessários do processo. |

O systemd não executa o cron diretamente. Ele mantém ativo o scheduler; o scheduler decide quais comandos `docker exec` devem ocorrer.

## 11. Arquivos no servidor depois da instalação

```text
/home/projetos/moodle-docker/
├── docker-compose.instituicoes.yml
├── scripts/moodle-cron-scheduler.sh
├── systemd/moodle-cron-scheduler.service
└── config/moodle-cron-scheduler.env.example

/usr/local/sbin/
└── moodle-cron-scheduler              cópia executável instalada

/etc/default/
└── moodle-cron-scheduler              configuração local do servidor

/etc/systemd/system/
└── moodle-cron-scheduler.service      unidade instalada do systemd

/run/moodle-cron-scheduler/
├── scheduler.lock
├── capacity-1.lock
├── capacity-2.lock
└── tenant-*.lock
```

O diretório `/run` é temporário: ele é recriado em cada boot. Isso é desejável para locks; eles não devem sobreviver a um reinício. O systemd recria o diretório por meio de `RuntimeDirectory`.

## 12. Implantação no servidor, com o motivo de cada etapa

### Etapa 1: atualizar e validar o projeto

```sh
cd /home/projetos/moodle-docker
git pull
git status
bash -n scripts/moodle-cron-scheduler.sh
./tests/test-moodle-cron-scheduler.sh
docker compose -f docker-compose.instituicoes.yml config --quiet
```

`bash -n` verifica a sintaxe sem executar o script. O teste usa um Docker simulado para validar descoberta e balanceamento, sem tocar em containers reais.

### Etapa 2: marcar todas as instituições

Edite `docker-compose.instituicoes.yml` e acrescente o label a **cada** serviço Moodle de instituição:

```yaml
labels:
  com.w3soft.moodle.role: tenant
```

Depois aplique a configuração:

```sh
cd /home/projetos/moodle-docker
docker compose -f docker-compose.instituicoes.yml up -d
```

Esse comando pode recriar containers cujos labels mudaram. Os dados persistem porque o Moodle usa volumes Docker externos, como `moodledata_*`; ainda assim, faça isso em horário conhecido e verifique a disponibilidade das escolas.

Confirme a descoberta pelo próprio Docker:

```sh
docker ps \
  --filter status=running \
  --filter label=com.w3soft.moodle.role=tenant \
  --format '{{.Names}}'
```

### Etapa 3: instalar o programa e a unidade

Os arquivos versionados do projeto não devem ser executados diretamente pelo systemd, pois o projeto pode ser atualizado, ter permissões alteradas ou ser movido. Por isso, o script é copiado para `/usr/local/sbin` e a unidade para o diretório padrão do systemd:

```sh
cd /home/projetos/moodle-docker

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

Os números de permissão significam:

- `0750`: root pode ler, escrever e executar; o grupo pode ler e executar;
- `0644`: root pode alterar; os demais podem apenas ler.

O arquivo `/etc/default/moodle-cron-scheduler` é configuração local. Em atualizações futuras, atualize script e unidade, mas não o sobrescreva sem revisar seus limites de concorrência.

### Etapa 4: remover mecanismos antigos

O ponto mais importante da migração é garantir que exista apenas **um** agendador. Dois mecanismos podem chamar o cron da mesma instituição ao mesmo tempo.

```sh
docker ps -a --format '{{.Names}}' | sort | grep '_cron$' || true
sudo crontab -l || true
crontab -l || true
```

Remova do crontab qualquer linha que use os antigos scripts ou execute `admin/cli/cron.php`. Para containers `_cron`, remova somente nomes confirmados na listagem, por exemplo:

```sh
docker rm -f moodle_colegio_modelo_cron
```

Não use um comando de remoção genérico nem `docker compose --remove-orphans`. Os arquivos de infraestrutura e instituições podem pertencer ao mesmo projeto Compose, e uma remoção ampla pode afetar proxy, banco ou Redis.

### Etapa 5: validar antes de deixar permanente

Primeiro, valide a unidade:

```sh
sudo systemd-analyze verify \
  /etc/systemd/system/moodle-cron-scheduler.service
```

Depois valide descoberta e distribuição sem executar PHP:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --discover
sudo /usr/local/sbin/moodle-cron-scheduler --dry-run
```

Por fim, teste um ciclo real. Ele aguarda o próximo minuto para respeitar as janelas de 0, 15, 30 e 45 segundos:

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --once
```

Não deixe o serviço permanente ligado enquanto testa `--once`, pois o lock global impede duas instâncias do scheduler.

### Etapa 6: ativar no boot

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now moodle-cron-scheduler.service
sudo systemctl status moodle-cron-scheduler.service
```

Os comandos têm significados distintos:

- `daemon-reload`: pede ao systemd que releia os arquivos de unidade;
- `enable`: configura o início automático no próximo boot;
- `--now`: inicia também neste momento;
- `status`: mostra se o processo está rodando e seus últimos logs.

O estado esperado é `active (running)`.

### Etapa 7: observar os primeiros minutos

```sh
sudo journalctl -u moodle-cron-scheduler.service -f
```

| Evento | Significado |
|---|---|
| `event=discovery` | Quantidade de tenants encontrada no minuto. |
| `event=assignment` | Tenant e janela planejada. |
| `event=cron_start` | O comando PHP iniciou. |
| `event=cron_finish result=success` | O cron terminou com sucesso. |
| `event=cron_finish result=failure` | O comando retornou erro. |
| `reason=previous_execution_running` | O cron anterior do mesmo tenant ainda estava ativo. |
| `reason=capacity_timeout` | Não houve vaga de concorrência no tempo configurado. |

## 13. Configuração e ajuste de capacidade

O arquivo `/etc/default/moodle-cron-scheduler` é lido pelo systemd quando o serviço inicia.

| Variável | Valor inicial | Função |
|---|---:|---|
| `MOODLE_CRON_DISCOVERY_MODE` | `label` | Descobre tenants pelo label Docker. |
| `MOODLE_CRON_TENANT_LABEL` | `com.w3soft.moodle.role=tenant` | Define o label e valor exigidos. |
| `MOODLE_CRON_MAX_PARALLEL` | `2` | Máximo global de cron.php simultâneos. |
| `MOODLE_CRON_QUEUE_TIMEOUT_SECONDS` | `50` | Tempo máximo aguardando uma vaga. |
| `MOODLE_CRON_COMMAND_TIMEOUT_SECONDS` | `0` | Zero deixa o cron terminar naturalmente. |
| `MOODLE_CRON_SLOW_WARNING_SECONDS` | `60` | Duração que gera aviso de lentidão. |

Para alterar uma configuração:

```sh
sudo nano /etc/default/moodle-cron-scheduler
sudo systemctl restart moodle-cron-scheduler.service
sudo systemctl status moodle-cron-scheduler.service
```

Comece com duas execuções simultâneas. Se houver muitos `capacity_timeout`, observe os recursos antes de aumentar o limite:

```sh
docker stats
uptime
free -h
```

Se CPU, memória, disco e MariaDB estiverem confortáveis, aumente de `2` para `3`, acompanhe os logs e só então considere `4`. Não aumente diretamente para um valor alto: cada cron pode usar banco, Redis e sistema de arquivos ao mesmo tempo.

## 14. Diagnóstico guiado

### O serviço não inicia

```sh
sudo systemctl status moodle-cron-scheduler.service
sudo journalctl -u moodle-cron-scheduler.service -b --no-pager
```

Verifique se Docker, Bash e `flock` existem e se o script foi instalado em `/usr/local/sbin/moodle-cron-scheduler`.

### Nenhuma instituição foi descoberta

```sh
sudo /usr/local/sbin/moodle-cron-scheduler --discover
docker ps --format '{{.Names}}\t{{.Labels}}'
```

Confirme que cada tenant está `running`, possui exatamente o label `com.w3soft.moodle.role=tenant` e foi recriado depois da alteração no Compose.

### Uma instituição não recebe cron

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since '15 minutes ago' \
  --no-pager | grep 'tenant=moodle_colegio_modelo'
```

Procure por `container_not_eligible`, `previous_execution_running` ou `capacity_timeout`. Também teste manualmente:

```sh
docker exec -u www-data moodle_colegio_modelo \
  php /var/www/html/admin/cli/cron.php --keep-alive=0
```

### Muitos `capacity_timeout`

Isso significa que o servidor recebeu mais trabalho do que consegue executar no limite atual. Não é falha do lock: é um sinal para rever concorrência, recursos do servidor ou tarefas lentas.

### Muitos `previous_execution_running`

Isso indica que crons estão demorando mais de um minuto. O lock está funcionando, mas a causa da lentidão deve ser investigada: tarefas Moodle pesadas, filas acumuladas, banco lento, integrações externas ou falta de recursos.

## 15. Operação do dia a dia

Verificar se o serviço está ativo:

```sh
sudo systemctl is-active moodle-cron-scheduler.service
```

Reiniciar após alterar configuração:

```sh
sudo systemctl restart moodle-cron-scheduler.service
```

Ver logs das últimas duas horas:

```sh
sudo journalctl \
  -u moodle-cron-scheduler.service \
  --since '2 hours ago' \
  --no-pager
```

Depois de criar uma nova instituição, o procedimento adicional de cron é somente:

1. declarar o label de tenant no Compose;
2. subir o container;
3. confirmar com `--discover`.

Não é necessário criar outro container cron, editar uma lista manual nem criar uma nova entrada de `crontab`.

## 16. Resumo para lembrar

```text
Moodle precisa do cron para executar trabalho pendente.
Cada instituição precisa de seu próprio cron.php.
O host descobre instituições por label Docker.
As execuções são espalhadas no minuto para reduzir picos.
O limite de concorrência protege os recursos do servidor.
Locks impedem duas execuções do mesmo tenant.
systemd mantém o scheduler ativo, inicia no boot e fornece logs.
```
