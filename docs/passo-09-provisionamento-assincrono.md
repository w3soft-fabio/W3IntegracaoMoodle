# Passo 9: Provisionamento assincrono de instituicoes

## Objetivo deste passo

Neste passo, o objetivo e transformar a criacao de uma nova instituicao em um fluxo controlado de provisionamento assincrono.

A ideia principal e:

```text
Antes:
  API recebe a requisicao
  API altera arquivos
  API sobe container diretamente
  API tenta devolver sucesso ou erro na mesma chamada HTTP

Depois:
  API recebe a requisicao
  API grava a instituicao com status Pending
  API cria um job de provisionamento
  Worker executa as etapas em background
  Worker marca a instituicao como Active somente depois dos healthchecks
```

Esse modelo reduz risco operacional porque a criacao de uma instituicao envolve varios recursos diferentes:

- banco de dados;
- usuario e senha de banco;
- arquivo de secrets ou secret manager;
- volume `moodledata`;
- container Moodle;
- rota no proxy;
- configuracao de cron;
- validacao de saude da aplicacao.

Essas operacoes nao devem depender de uma unica requisicao HTTP aberta ate o final.

## Problema que este passo resolve

Se o service .NET criar arquivos e subir containers diretamente durante a requisicao, alguns problemas aparecem em producao:

- a requisicao pode expirar no meio do processo;
- o banco pode ser criado, mas o container falhar;
- o container pode subir, mas a rota do proxy nao ser atualizada;
- duas requisicoes simultaneas podem editar o mesmo arquivo Compose ou Caddyfile;
- uma falha parcial pode deixar recursos orfaos;
- nao fica claro em qual etapa o processo parou;
- fica dificil repetir a operacao com seguranca;
- fica dificil auditar quem criou cada instituicao;
- o service .NET passa a ter permissoes muito sensiveis sobre Docker, banco e secrets.

O provisionamento assincrono troca esse comportamento por um fluxo com estado persistido, retry, logs e healthcheck.

## Arquitetura recomendada

Fluxo geral:

```text
Cliente/Admin
   |
   | POST /institutions
   v
API .NET
   |
   | grava Institution com status Pending
   | cria ProvisioningJob com status Queued
   v
Banco da plataforma
   |
   v
Worker/Provisioner
   |
   | executa etapas idempotentes
   v
Docker / MariaDB / Secrets / Caddy
   |
   v
Institution status Active ou Failed
```

Neste desenho existem dois tipos de banco:

- banco da plataforma: guarda instituicoes, jobs, status, auditoria e configuracoes operacionais;
- bancos Moodle: um banco logico por instituicao, por exemplo `moodle_escola_a`.

O banco da plataforma nao substitui os bancos Moodle. Ele serve para controlar a automacao.

## Estados da instituicao

A instituicao deve ter um status claro.

Estados recomendados:

```text
Pending       pedido recebido, mas ainda nao executado
Provisioning worker iniciou o provisionamento
Active        Moodle pronto para uso
Failed        provisionamento falhou
Suspended     instituicao pausada administrativamente
Deleting      remocao em andamento
Deleted       removida logicamente, se o historico for mantido
```

O status deve refletir o estado real do ambiente. A instituicao so deve virar `Active` depois que o worker confirmar que o Moodle esta acessivel e saudavel.

## Entidade Institution

Exemplo conceitual em C#:

```csharp
public enum InstitutionStatus
{
    Pending,
    Provisioning,
    Active,
    Failed,
    Suspended,
    Deleting,
    Deleted
}

public sealed class Institution
{
    public Guid Id { get; set; }

    public string Name { get; set; } = default!;
    public string Slug { get; set; } = default!;
    public string TenantKey { get; set; } = default!;

    public string PublicUrl { get; set; } = default!;

    public string DatabaseName { get; set; } = default!;
    public string DatabaseUser { get; set; } = default!;

    public string ContainerName { get; set; } = default!;
    public string VolumeName { get; set; } = default!;
    public string RedisPrefix { get; set; } = default!;

    public InstitutionStatus Status { get; set; }

    public string? LastError { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ActivatedAt { get; set; }
}
```

Campos importantes:

- `Id`: identificador interno da instituicao;
- `Slug`: identificador publico usado na URL, como `escola-a`;
- `TenantKey`: identificador tecnico imutavel, que nao deve depender do nome publico;
- `PublicUrl`: URL final da instituicao;
- `DatabaseName`: banco Moodle exclusivo da instituicao;
- `DatabaseUser`: usuario exclusivo do banco Moodle;
- `ContainerName`: nome do container Moodle;
- `VolumeName`: volume `moodledata` exclusivo;
- `RedisPrefix`: prefixo Redis exclusivo;
- `Status`: estado atual da instituicao.

## Entidade ProvisioningJob

O job representa uma tentativa de provisionamento.

Exemplo conceitual:

```csharp
public enum ProvisioningJobStatus
{
    Queued,
    Running,
    Succeeded,
    Failed
}

public sealed class ProvisioningJob
{
    public Guid Id { get; set; }
    public Guid InstitutionId { get; set; }

    public ProvisioningJobStatus Status { get; set; }

    public int AttemptCount { get; set; }
    public string? CurrentStep { get; set; }
    public string? Error { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? FinishedAt { get; set; }
}
```

Essa tabela permite saber:

- quais instituicoes aguardam provisionamento;
- quais estao em execucao;
- em qual etapa cada uma parou;
- qual erro ocorreu;
- quantas tentativas ja foram feitas.

## Entidade ProvisioningStep

Para rastreamento mais detalhado, cada etapa pode ser salva separadamente.

Exemplo conceitual:

```csharp
public sealed class ProvisioningStep
{
    public Guid Id { get; set; }
    public Guid JobId { get; set; }

    public string StepName { get; set; } = default!;
    public string Status { get; set; } = default!;
    public string? Error { get; set; }

    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? FinishedAt { get; set; }
}
```

Valores possiveis para `Status`:

```text
Pending
Running
Succeeded
Failed
Skipped
```

Essa tabela e util para auditoria, suporte e retry.

## Endpoint de criacao

O endpoint de criacao deve apenas registrar o pedido.

Exemplo:

```http
POST /institutions
Content-Type: application/json
```

Request:

```json
{
  "name": "Escola A",
  "slug": "escola-a",
  "adminName": "Maria",
  "adminEmail": "maria@escola.com"
}
```

Responsabilidades do endpoint:

- validar o `slug`;
- validar se o `slug` ja existe;
- gerar identificadores tecnicos;
- criar `Institution` com status `Pending`;
- criar `ProvisioningJob` com status `Queued`;
- publicar mensagem na fila, se houver fila externa;
- retornar `202 Accepted`.

Resposta recomendada:

```http
HTTP/1.1 202 Accepted
```

```json
{
  "institutionId": "f4c4a62d-62d4-41d1-a8ff-3c69d018c917",
  "status": "Pending",
  "statusUrl": "/institutions/f4c4a62d-62d4-41d1-a8ff-3c69d018c917/status"
}
```

O codigo `202 Accepted` e mais adequado que `201 Created`, porque a instituicao ainda nao esta pronta para uso.

## Endpoint de status

O cliente administrativo deve conseguir consultar o andamento.

Exemplo:

```http
GET /institutions/{id}/status
```

Resposta durante o provisionamento:

```json
{
  "id": "f4c4a62d-62d4-41d1-a8ff-3c69d018c917",
  "name": "Escola A",
  "slug": "escola-a",
  "status": "Provisioning",
  "currentStep": "StartContainer",
  "publicUrl": "https://seudominio.com/i/escola-a",
  "lastError": null
}
```

Resposta em caso de erro:

```json
{
  "id": "f4c4a62d-62d4-41d1-a8ff-3c69d018c917",
  "name": "Escola A",
  "slug": "escola-a",
  "status": "Failed",
  "currentStep": "ConfigureProxy",
  "publicUrl": "https://seudominio.com/i/escola-a",
  "lastError": "Caddy reload failed"
}
```

## Worker de provisionamento

Para comecar simples, o worker pode ser um `BackgroundService` do proprio .NET lendo uma tabela de jobs no banco.

Exemplo conceitual:

```csharp
public sealed class ProvisioningWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;

    public ProvisioningWorker(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            using var scope = _scopeFactory.CreateScope();

            var provisioner = scope.ServiceProvider
                .GetRequiredService<TenantProvisioner>();

            await provisioner.ProcessNextJobAsync(stoppingToken);

            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}
```

Opcoes possiveis para execucao de jobs:

- `BackgroundService` com tabela no banco;
- Hangfire;
- Quartz.NET;
- RabbitMQ;
- Redis Queue;
- SQS, se a infraestrutura estiver na AWS.

Para uma primeira versao em servidor unico, a opcao mais simples e `BackgroundService` com tabela no banco. Ela reduz dependencias externas e ja permite status, retry e auditoria.

## Pipeline de provisionamento

O provisionamento deve ser dividido em etapas pequenas.

Pipeline recomendado:

```text
1. MarkInstitutionAsProvisioning
2. GenerateSecrets
3. CreateDatabase
4. CreateDatabaseUser
5. GrantDatabasePermissions
6. StoreSecrets
7. CreateMoodleVolume
8. CreateOrUpdateServiceDefinition
9. StartContainer
10. ConfigureProxy
11. ReloadProxy
12. RunMoodleInstallOrBootstrap
13. RunHealthcheck
14. MarkInstitutionAsActive
```

Cada etapa deve atualizar o job antes de executar.

Exemplo conceitual:

```csharp
public sealed class TenantProvisioner
{
    private readonly AppDbContext _db;
    private readonly DatabaseProvisioningService _database;
    private readonly SecretService _secrets;
    private readonly DockerComposeService _docker;
    private readonly ProxyConfigService _proxy;
    private readonly HealthcheckService _healthcheck;

    public async Task ProcessNextJobAsync(CancellationToken ct)
    {
        var job = await GetNextQueuedJobAsync(ct);
        if (job is null)
        {
            return;
        }

        try
        {
            job.Status = ProvisioningJobStatus.Running;
            job.StartedAt = DateTimeOffset.UtcNow;

            var institution = await _db.Institutions.FindAsync([job.InstitutionId], ct)
                ?? throw new InvalidOperationException("Institution not found.");

            institution.Status = InstitutionStatus.Provisioning;
            await _db.SaveChangesAsync(ct);

            await RunStep(job, "GenerateSecrets", () =>
                _secrets.GenerateAndStoreAsync(institution, ct));

            await RunStep(job, "CreateDatabase", () =>
                _database.CreateDatabaseAsync(institution, ct));

            await RunStep(job, "CreateDatabaseUser", () =>
                _database.CreateUserAndGrantAsync(institution, ct));

            await RunStep(job, "CreateService", () =>
                _docker.CreateOrUpdateTenantAsync(institution, ct));

            await RunStep(job, "ConfigureProxy", () =>
                _proxy.AddTenantRouteAndReloadAsync(institution, ct));

            await RunStep(job, "Healthcheck", () =>
                _healthcheck.WaitUntilHealthyAsync(institution, ct));

            institution.Status = InstitutionStatus.Active;
            institution.ActivatedAt = DateTimeOffset.UtcNow;

            job.Status = ProvisioningJobStatus.Succeeded;
            job.FinishedAt = DateTimeOffset.UtcNow;

            await _db.SaveChangesAsync(ct);
        }
        catch (Exception ex)
        {
            await MarkFailedAsync(job, ex, ct);
        }
    }
}
```

Exemplo simplificado de `RunStep`:

```csharp
private async Task RunStep(
    ProvisioningJob job,
    string stepName,
    Func<Task> action)
{
    job.CurrentStep = stepName;
    await _db.SaveChangesAsync();

    await action();
}
```

Em uma implementacao completa, `RunStep` tambem deve gravar a tabela `ProvisioningSteps`.

## Idempotencia

As etapas devem ser idempotentes.

Idempotencia significa que a mesma etapa pode rodar mais de uma vez sem corromper o ambiente.

Exemplos:

- se o banco ja existe, a etapa considera isso como sucesso;
- se o usuario ja existe, a etapa valida ou atualiza a senha;
- se o volume ja existe, ele e reutilizado;
- se o container ja existe e esta correto, ele e mantido;
- se a rota do proxy ja existe, ela e validada;
- se o healthcheck falha, o tenant nao vira `Active`.

Isso e essencial porque falhas parciais acontecem. O retry deve continuar o processo com seguranca, nao criar recursos duplicados.

## Criacao de banco e usuario

Cada instituicao deve ter banco e usuario exclusivos.

Exemplo de SQL:

```sql
CREATE DATABASE IF NOT EXISTS `moodle_escola_a`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-gerada';

ALTER USER 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-gerada';

GRANT ALL PRIVILEGES ON `moodle_escola_a`.*
  TO 'moodle_escola_a'@'%';

FLUSH PRIVILEGES;
```

O Moodle da instituicao deve receber apenas credenciais restritas:

```text
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-gerada
```

A credencial root ou administrativa do MariaDB deve ficar disponivel somente para o provisionador.

## Geracao de credenciais

As senhas devem ser geradas pelo provisionador, nao recebidas prontas na requisicao.

Exemplo:

```csharp
using System.Security.Cryptography;

public static string GenerateSecret(int bytes = 32)
{
    return Convert.ToBase64String(RandomNumberGenerator.GetBytes(bytes));
}
```

Credenciais e identificadores que podem ser gerados:

- senha do banco da instituicao;
- senha inicial do administrador Moodle, se a instalacao for automatizada;
- prefixo Redis;
- tokens internos;
- `TenantKey` tecnico.

Esses valores nao devem ser logados.

## Armazenamento de secrets

Em producao, `env_file` do Docker Compose nao deve ser tratado como cofre de secrets. Ele apenas injeta variaveis de ambiente no container.

Opcoes melhores:

- Docker secrets, se usar Docker Swarm;
- Kubernetes Secrets, se usar Kubernetes;
- HashiCorp Vault;
- AWS Secrets Manager;
- GCP Secret Manager;
- Azure Key Vault;
- SOPS para arquivos criptografados.

Para uma primeira versao em servidor unico, ainda e possivel usar arquivos locais, desde que com regras rigidas:

```text
/opt/w3soft/secrets/tenants/escola-a.env
owner: usuario-do-provisionador
mode: 600
nao versionado
backup criptografado
sem logs do conteudo
```

Os arquivos atuais em `secrets/*.env` sao adequados para laboratorio, mas nao devem ser a unica estrategia de seguranca em producao.

## Compose por tenant

No projeto atual existe um arquivo `docker-compose.instituicoes.yml` com varios servicos Moodle.

Para provisionamento automatico, e mais seguro gerar um Compose por instituicao.

Exemplo de estrutura:

```text
/opt/w3soft/tenants/
  escola-a/
    docker-compose.yml
    generated.json

  escola-b/
    docker-compose.yml
    generated.json

/opt/w3soft/secrets/
  tenants/
    escola-a.env
    escola-b.env
```

Exemplo de Compose por tenant:

```yaml
services:
  moodle_escola_a:
    image: w3soft/moodle:2026.06.1-local
    container_name: moodle_escola_a
    restart: unless-stopped
    env_file:
      - /opt/w3soft/secrets/tenants/escola-a.env
    volumes:
      - moodledata_escola_a:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_a:
    name: moodledata_escola_a

networks:
  moodle_net:
    external: true
```

Com esse modelo, o provisionador pode subir uma instituicao especifica:

```sh
docker compose -p tenant_escola_a -f /opt/w3soft/tenants/escola-a/docker-compose.yml up -d
```

Vantagens:

- reduz conflito entre provisionamentos simultaneos;
- evita editar um arquivo Compose gigante;
- facilita remover ou recriar uma instituicao especifica;
- facilita auditoria por tenant;
- facilita backup dos metadados gerados.

## Configuracao do proxy

O proxy nao deve ser editado manualmente para cada nova instituicao em producao.

O worker pode gerar o Caddyfile a partir das instituicoes cadastradas.

Exemplo conceitual:

```caddyfile
seudominio.com {
    handle /i/escola-a/* {
        reverse_proxy moodle_escola_a:80
    }

    handle /i/escola-b/* {
        reverse_proxy moodle_escola_b:80
    }
}
```

Fluxo seguro para atualizar o proxy:

```text
1. buscar instituicoes Active e Provisioning
2. gerar Caddyfile.tmp
3. validar Caddyfile.tmp
4. substituir Caddyfile ativo de forma atomica
5. recarregar Caddy
6. rodar healthcheck da URL publica
```

Nao e recomendado escrever diretamente sobre o arquivo ativo sem validacao. Um erro de sintaxe poderia derrubar as rotas de todas as instituicoes.

## Healthcheck

Depois de subir container e proxy, o worker deve validar se a instituicao esta realmente pronta.

Verificacoes recomendadas:

- container esta em execucao;
- porta interna responde;
- URL publica responde;
- Moodle conecta no banco;
- Moodle consegue escrever no `moodledata`;
- Redis responde, se configurado;
- pagina inicial nao retorna erro 500;
- instalacao/bootstrap do Moodle foi concluida.

Exemplo conceitual:

```csharp
var response = await httpClient.GetAsync("https://seudominio.com/i/escola-a/");

if (!response.IsSuccessStatusCode)
{
    throw new ProvisioningException("Moodle public URL did not become healthy.");
}
```

Enquanto o healthcheck nao passar, a instituicao deve continuar como `Provisioning` ou virar `Failed`.

## Retry e falha parcial

Provisionamento de infraestrutura nao e uma transacao unica. Nao existe um `ROLLBACK` simples que desfaça Docker, MariaDB, secrets e proxy ao mesmo tempo.

Por isso, a estrategia deve ser:

- etapas idempotentes;
- status persistido;
- retry manual ou automatico;
- logs claros;
- compensacao apenas quando for segura.

Exemplo:

```text
Falhou depois de criar banco e usuario.

Retry:
  banco ja existe: ok
  usuario ja existe: ok
  senha validada ou atualizada: ok
  container ainda nao existe: criar
  proxy ainda nao existe: configurar
```

Rollback automatico pode ser perigoso, principalmente se a instituicao ja tiver dados. Para o inicio, e mais seguro marcar como `Failed` e oferecer acoes administrativas.

Endpoints administrativos possiveis:

```http
POST /institutions/{id}/retry-provisioning
POST /institutions/{id}/suspend
POST /institutions/{id}/delete
```

## Seguranca do provisionador

O provisionador e um componente sensivel porque pode:

- criar banco;
- criar usuario;
- alterar secrets;
- subir container;
- alterar proxy;
- executar comandos Docker.

Regras obrigatorias:

- nao expor o provisionador publicamente sem autenticacao forte;
- separar endpoints administrativos de endpoints publicos;
- validar rigorosamente todos os campos da requisicao;
- nunca permitir que a requisicao escolha imagem Docker arbitraria;
- nunca permitir que a requisicao escolha comando de container arbitrario;
- nunca permitir volumes arbitrarios informados pelo usuario;
- usar allowlist de imagem, rede, dominio e limites de recursos;
- nao logar secrets;
- registrar auditoria de quem criou ou alterou uma instituicao;
- proteger o acesso ao Docker socket;
- restringir a credencial administrativa do banco ao provisionador.

Se o provisionador tiver acesso a `/var/run/docker.sock`, trate esse acesso como equivalente a controle administrativo do host. Esse componente deve ficar isolado e protegido.

## Validacao do slug

O `slug` deve ser seguro para URL, nome de container, nome de arquivo e rota do proxy.

Exemplo de validacao:

```csharp
private static readonly Regex SlugRegex =
    new("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", RegexOptions.Compiled);
```

Aceitar:

```text
escola-a
colegio-santos-2026
empresa-treinamentos
```

Rejeitar:

```text
../etc/passwd
escola a
escola_a
; rm -rf /
https://outro-site.com
```

Mesmo com slug valido, nomes tecnicos devem ser gerados pelo sistema.

Exemplo:

```text
Slug publico: escola-a
Container: moodle_escola_a
Banco: moodle_escola_a
Volume: moodledata_escola_a
Redis prefix: escola_a_
TenantKey: uuid ou hash imutavel
```

## Estrutura de arquivos recomendada

Para uma evolucao pratica do projeto atual:

```text
/opt/w3soft/
  platform/
    docker-compose.infra.yml

  tenants/
    escola-a/
      docker-compose.yml
      generated.json

    escola-b/
      docker-compose.yml
      generated.json

  secrets/
    tenants/
      escola-a.env
      escola-b.env

  proxy/
    Caddyfile.generated
```

No repositorio, manter apenas templates e documentacao:

```text
templates/
  tenant-compose.yml.tpl
  caddy-route.tpl
```

Arquivos reais com secrets e configuracoes geradas devem ficar fora do Git.

## Sequencia completa

Fluxo completo de criacao:

```text
1. Admin chama POST /institutions com nome e slug.
2. API valida slug e unicidade.
3. API cria Institution com status Pending.
4. API cria ProvisioningJob com status Queued.
5. Worker pega o job.
6. Worker marca Institution como Provisioning.
7. Worker gera senha do banco e demais secrets.
8. Worker grava secrets em Secret Manager ou arquivo 600.
9. Worker cria banco moodle_escola_a.
10. Worker cria usuario moodle_escola_a.
11. Worker concede permissao somente no banco da escola.
12. Worker gera Compose do tenant.
13. Worker sobe container Moodle.
14. Worker gera ou atualiza rota no Caddy.
15. Worker recarrega proxy.
16. Worker roda instalacao/bootstrap do Moodle, se aplicavel.
17. Worker roda healthcheck.
18. Worker marca Institution como Active.
19. Admin consulta a URL final.
```

## Plano incremental para este projeto

Para evoluir sem reescrever toda a infraestrutura:

```text
1. Criar banco da plataforma com Institutions e ProvisioningJobs.
2. Criar endpoint POST /institutions retornando 202 Accepted.
3. Criar endpoint GET /institutions/{id}/status.
4. Criar BackgroundService para processar jobs.
5. Gerar credenciais fortes por instituicao.
6. Parar de editar um unico docker-compose.instituicoes.yml.
7. Gerar um Compose por tenant.
8. Gerar secrets por tenant com permissao 600.
9. Gerar Caddyfile a partir das instituicoes cadastradas.
10. Validar e recarregar o proxy de forma segura.
11. Rodar healthcheck antes de marcar Active.
12. Criar retry administrativo para jobs Failed.
13. Adicionar auditoria.
14. Adicionar backups por instituicao.
```

Esse plano mantem o uso de Docker Compose no inicio, mas troca o processo manual por um provisionamento rastreavel e repetivel.

## Resultado esperado

Ao final desta evolucao:

- a API nao ficara presa ate o container subir;
- o usuario/admin podera acompanhar o status do provisionamento;
- falhas parciais serao visiveis;
- sera possivel executar retry com seguranca;
- secrets serao gerados e armazenados de forma mais controlada;
- cada instituicao tera recursos tecnicos previsiveis;
- o proxy sera atualizado por geracao controlada;
- a instituicao so ficara `Active` depois de healthcheck;
- o processo estara mais proximo de um padrao aceitavel para producao.

