# Orientacoes para implementar rotas de sincronizacao Moodle na API .NET

Este documento descreve uma forma simples, incremental e alinhada com a organizacao atual da `MoodleProvisioner.Api` para implementar as rotas de sincronizacao entre W3Escola e Moodle.

Ele usa como base:

- O plano de integracao em `docs/plano-integracao-w3escola-moodle.md`.
- A API .NET em `MoodleProvisioner/src/MoodleProvisioner.Api`.
- O exemplo funcional de consumo dos WebServices do Moodle em `examples/moodle-api-client-csharp/Program.cs`.

## Objetivo

Criar as rotas:

- `POST /api/instituicoes/{tenantId}/sync/full`
- `POST /api/instituicoes/{tenantId}/sync/usuarios`
- `POST /api/instituicoes/{tenantId}/sync/estrutura-academica`
- `POST /api/instituicoes/{tenantId}/sync/matriculas`
- `POST /api/instituicoes/{tenantId}/sync/professores`
- `POST /api/instituicoes/{tenantId}/sync/conteudos`
- `POST /api/instituicoes/{tenantId}/sync/notas`
- `POST /api/instituicoes/{tenantId}/sync/agenda`

A primeira versao deve priorizar rotas que podem ser implementadas diretamente com WebServices nativos do Moodle. Rotas que provavelmente dependem de API interna, plugin local ou regras ainda nao fechadas devem existir, mas retornar `501 Not Implemented`.

## Decisao recomendada

A solucao mais simples e coerente com o projeto atual e manter controllers finos e concentrar a regra em servicos.

Estrutura sugerida:

```text
Controllers/
  InstituicoesController.cs
  SincronizacaoController.cs

Dtos/
  RespostaSincronizacao.cs

Services/
  Moodle/
    IMoodleClient.cs
    MoodleClient.cs
    ConfiguracaoMoodleTenant.cs
    IConfiguracaoMoodleTenant.cs
    OpcoesMoodleTenant.cs

  Sincronizacao/
    ISincronizadorMoodle.cs
    SincronizadorMoodle.cs
```

O projeto atual ja usa este estilo:

- `Controllers/InstituicoesController.cs` recebe a requisicao e chama um servico.
- `Services/ProvisionadorInstituicao/ProvisionadorInstituicao.cs` concentra a orquestracao.
- `Program.cs` registra dependencias com `builder.Services`.

Portanto, a sincronizacao deve seguir o mesmo padrao, sem criar uma arquitetura maior neste momento.

## Rotas e comportamento inicial

Implementar as rotas com estes comportamentos:

| Rota | Status inicial recomendado | Motivo |
| --- | --- | --- |
| `POST /sync/full` | `200 OK` ou `202 Accepted` | Pode orquestrar as sincronizacoes ja suportadas. Em v1 simples, `200 OK` e suficiente. |
| `POST /sync/usuarios` | `200 OK` | Pode usar `core_user_get_users_by_field`, `core_user_create_users`, `core_user_update_users`. |
| `POST /sync/estrutura-academica` | `200 OK` | Pode usar categorias, cursos, cohorts e grupos nativos do Moodle. |
| `POST /sync/matriculas` | `200 OK` | Pode usar `enrol_manual_enrol_users` e `enrol_manual_unenrol_users`. |
| `POST /sync/professores` | `200 OK` | Pode usar usuarios + matricula com papel de professor. |
| `POST /sync/conteudos` | `501 Not Implemented` | Publicacao robusta de arquivos, recursos, paginas e atividades tende a exigir plugin/API interna ou modelagem adicional. |
| `POST /sync/notas` | `501 Not Implemented` | Depende da regra de fonte oficial, mapeamento de itens de nota e possivelmente integracao mais especifica com gradebook. |
| `POST /sync/agenda` | `501 Not Implemented` | Pode exigir decisao entre calendario Moodle, eventos por curso, eventos por grupo e origem oficial da agenda. |

## Controller recomendado

Criar `Controllers/SincronizacaoController.cs`:

```csharp
using Microsoft.AspNetCore.Mvc;
using MoodleProvisioner.Api.Dtos;
using MoodleProvisioner.Api.Services;

namespace MoodleProvisioner.Api.Controllers;

[ApiController]
[Route("api/instituicoes/{tenantId}/sync")]
public sealed class SincronizacaoController(ISincronizadorMoodle sincronizador) : ControllerBase
{
    [HttpPost("full")]
    public async Task<IActionResult> Full(string tenantId, CancellationToken cancellationToken)
    {
        var resultado = await sincronizador.SincronizarFullAsync(tenantId, cancellationToken);
        return Ok(resultado);
    }

    [HttpPost("usuarios")]
    public async Task<IActionResult> Usuarios(string tenantId, CancellationToken cancellationToken)
    {
        var resultado = await sincronizador.SincronizarUsuariosAsync(tenantId, cancellationToken);
        return Ok(resultado);
    }

    [HttpPost("estrutura-academica")]
    public async Task<IActionResult> EstruturaAcademica(string tenantId, CancellationToken cancellationToken)
    {
        var resultado = await sincronizador.SincronizarEstruturaAcademicaAsync(tenantId, cancellationToken);
        return Ok(resultado);
    }

    [HttpPost("matriculas")]
    public async Task<IActionResult> Matriculas(string tenantId, CancellationToken cancellationToken)
    {
        var resultado = await sincronizador.SincronizarMatriculasAsync(tenantId, cancellationToken);
        return Ok(resultado);
    }

    [HttpPost("professores")]
    public async Task<IActionResult> Professores(string tenantId, CancellationToken cancellationToken)
    {
        var resultado = await sincronizador.SincronizarProfessoresAsync(tenantId, cancellationToken);
        return Ok(resultado);
    }

    [HttpPost("conteudos")]
    public IActionResult Conteudos(string tenantId)
    {
        return StatusCode(StatusCodes.Status501NotImplemented, RespostaSincronizacao.NaoImplementado(
            tenantId,
            "conteudos",
            "Publicacao de conteudos no Moodle provavelmente exigira API interna, plugin local ou modelagem especifica de recursos/atividades."
        ));
    }

    [HttpPost("notas")]
    public IActionResult Notas(string tenantId)
    {
        return StatusCode(StatusCodes.Status501NotImplemented, RespostaSincronizacao.NaoImplementado(
            tenantId,
            "notas",
            "Sincronizacao de notas depende da regra de fonte oficial, mapeamento de itens de nota e integracao especifica com o gradebook."
        ));
    }

    [HttpPost("agenda")]
    public IActionResult Agenda(string tenantId)
    {
        return StatusCode(StatusCodes.Status501NotImplemented, RespostaSincronizacao.NaoImplementado(
            tenantId,
            "agenda",
            "Sincronizacao de agenda depende da decisao entre calendario Moodle, eventos por curso/grupo e origem oficial da agenda."
        ));
    }
}
```

## DTO de resposta

Criar `Dtos/RespostaSincronizacao.cs`:

```csharp
namespace MoodleProvisioner.Api.Dtos;

public sealed record RespostaSincronizacao(
    string Status,
    string TenantId,
    string Tipo,
    string Mensagem,
    DateTimeOffset IniciadoEm,
    DateTimeOffset FinalizadoEm,
    IReadOnlyList<string> Avisos
)
{
    public static RespostaSincronizacao Concluido(string tenantId, string tipo, string mensagem, IReadOnlyList<string>? avisos = null)
    {
        var agora = DateTimeOffset.UtcNow;
        return new RespostaSincronizacao("completed", tenantId, tipo, mensagem, agora, agora, avisos ?? []);
    }

    public static RespostaSincronizacao NaoImplementado(string tenantId, string tipo, string mensagem)
    {
        var agora = DateTimeOffset.UtcNow;
        return new RespostaSincronizacao("not_implemented", tenantId, tipo, mensagem, agora, agora, []);
    }
}
```

Em uma versao posterior, esta resposta pode incluir contadores:

- Usuarios criados.
- Usuarios atualizados.
- Cursos criados.
- Matriculas criadas.
- Matriculas removidas.
- Erros por item.

## Interface do sincronizador

Criar `Services/Sincronizacao/ISincronizadorMoodle.cs`:

```csharp
using MoodleProvisioner.Api.Dtos;

namespace MoodleProvisioner.Api.Services;

public interface ISincronizadorMoodle
{
    Task<RespostaSincronizacao> SincronizarFullAsync(string tenantId, CancellationToken cancellationToken);
    Task<RespostaSincronizacao> SincronizarUsuariosAsync(string tenantId, CancellationToken cancellationToken);
    Task<RespostaSincronizacao> SincronizarEstruturaAcademicaAsync(string tenantId, CancellationToken cancellationToken);
    Task<RespostaSincronizacao> SincronizarMatriculasAsync(string tenantId, CancellationToken cancellationToken);
    Task<RespostaSincronizacao> SincronizarProfessoresAsync(string tenantId, CancellationToken cancellationToken);
}
```

Criar `Services/Sincronizacao/SincronizadorMoodle.cs`:

```csharp
using MoodleProvisioner.Api.Dtos;

namespace MoodleProvisioner.Api.Services;

public sealed class SincronizadorMoodle(
    IMoodleClient moodleClient,
    ILogger<SincronizadorMoodle> logger) : ISincronizadorMoodle
{
    public async Task<RespostaSincronizacao> SincronizarFullAsync(string tenantId, CancellationToken cancellationToken)
    {
        await SincronizarUsuariosAsync(tenantId, cancellationToken);
        await SincronizarProfessoresAsync(tenantId, cancellationToken);
        await SincronizarEstruturaAcademicaAsync(tenantId, cancellationToken);
        await SincronizarMatriculasAsync(tenantId, cancellationToken);

        return RespostaSincronizacao.Concluido(
            tenantId,
            "full",
            "Sincronizacao completa concluida para os modulos suportados nesta versao."
        );
    }

    public async Task<RespostaSincronizacao> SincronizarUsuariosAsync(string tenantId, CancellationToken cancellationToken)
    {
        logger.LogInformation("Iniciando sincronizacao de usuarios do tenant {TenantId}.", tenantId);

        // Buscar alunos/professores no W3Escola.
        // Para cada usuario:
        // 1. Buscar usuario no Moodle por username.
        // 2. Se nao existir, buscar conflitos por email/idnumber.
        // 3. Criar ou atualizar usuario.
        // Reaproveitar a logica do exemplo Program.cs.
        await moodleClient.CallAsync<JsonElement>(
            tenantId,
            "core_webservice_get_site_info",
            [],
            HttpMethod.Get,
            cancellationToken
        );

        return RespostaSincronizacao.Concluido(tenantId, "usuarios", "Sincronizacao de usuarios executada.");
    }

    public Task<RespostaSincronizacao> SincronizarEstruturaAcademicaAsync(string tenantId, CancellationToken cancellationToken)
    {
        // Implementar categorias, cursos e cohorts.
        return Task.FromResult(RespostaSincronizacao.Concluido(
            tenantId,
            "estrutura-academica",
            "Sincronizacao de estrutura academica executada."
        ));
    }

    public Task<RespostaSincronizacao> SincronizarMatriculasAsync(string tenantId, CancellationToken cancellationToken)
    {
        // Implementar matriculas de alunos nos cursos.
        return Task.FromResult(RespostaSincronizacao.Concluido(
            tenantId,
            "matriculas",
            "Sincronizacao de matriculas executada."
        ));
    }

    public Task<RespostaSincronizacao> SincronizarProfessoresAsync(string tenantId, CancellationToken cancellationToken)
    {
        // Implementar criacao/atualizacao de professores e enrolment com role teacher/editingteacher.
        return Task.FromResult(RespostaSincronizacao.Concluido(
            tenantId,
            "professores",
            "Sincronizacao de professores executada."
        ));
    }
}
```

Observacao: o exemplo acima usa `core_webservice_get_site_info` em `SincronizarUsuariosAsync` apenas como validacao inicial de conectividade. A implementacao real deve substituir os comentarios por chamadas aos dados do W3Escola e aos WebServices adequados do Moodle.

## Cliente Moodle

O `MoodleClient` deve ser extraido do exemplo `examples/moodle-api-client-csharp/Program.cs`.

Responsabilidades do cliente:

- Resolver configuracao do tenant.
- Montar endpoint `{BaseUrl}/webservice/rest/server.php`.
- Adicionar parametros obrigatorios:
  - `wstoken`
  - `wsfunction`
  - `moodlewsrestformat=json`
- Enviar `GET` com query string quando necessario.
- Enviar `POST` como `application/x-www-form-urlencoded`.
- Tratar erro Moodle retornado como JSON.
- Tratar erro Moodle retornado como XML.
- Validar status HTTP.
- Desserializar resposta para o tipo esperado.

Interface sugerida:

```csharp
using System.Text.Json;

namespace MoodleProvisioner.Api.Services;

public interface IMoodleClient
{
    Task<T> CallAsync<T>(
        string tenantId,
        string wsFunction,
        IEnumerable<KeyValuePair<string, string>> parameters,
        HttpMethod method,
        CancellationToken cancellationToken);
}
```

Configuracao por tenant:

```csharp
namespace MoodleProvisioner.Api.Services;

public sealed record OpcoesMoodleTenant(string BaseUrl, string Token);

public interface IConfiguracaoMoodleTenant
{
    OpcoesMoodleTenant Obter(string tenantId);
}
```

Implementacao inicial simples:

```csharp
namespace MoodleProvisioner.Api.Services;

public sealed class ConfiguracaoMoodleTenant(IConfiguration configuration) : IConfiguracaoMoodleTenant
{
    public OpcoesMoodleTenant Obter(string tenantId)
    {
        var baseUrl = configuration[$"MoodleTenants:{tenantId}:BaseUrl"];
        var token = configuration[$"MoodleTenants:{tenantId}:Token"];

        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            throw new InvalidOperationException($"URL do Moodle nao configurada para o tenant {tenantId}.");
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            throw new InvalidOperationException($"Token do Moodle nao configurado para o tenant {tenantId}.");
        }

        return new OpcoesMoodleTenant(baseUrl.TrimEnd('/'), token.Trim());
    }
}
```

Exemplo de configuracao:

```json
{
  "MoodleTenants": {
    "escola-demo": {
      "BaseUrl": "https://moodle.escola-demo.com.br",
      "Token": "TOKEN_DO_WEBSERVICE"
    }
  }
}
```

Em producao, o token deve vir de variavel de ambiente, secret manager ou storage seguro. O `appsettings.json` nao deve conter segredos reais.

## Registro de dependencias

Atualizar `Program.cs`:

```csharp
builder.Services.AddHttpClient<IMoodleClient, MoodleClient>();
builder.Services.AddSingleton<IConfiguracaoMoodleTenant, ConfiguracaoMoodleTenant>();
builder.Services.AddScoped<ISincronizadorMoodle, SincronizadorMoodle>();
```

O projeto ja possui `builder.Services.AddHttpClient();`. Ao registrar `AddHttpClient<IMoodleClient, MoodleClient>()`, o cliente passa a ser criado pelo `IHttpClientFactory`.

## WebServices Moodle por rota

### Usuarios

Funcoes provaveis:

- `core_user_get_users_by_field`
- `core_user_create_users`
- `core_user_update_users`

Regras recomendadas:

- `username = {tenantId}.aluno.{matricula}` para alunos.
- `username = {tenantId}.prof.{usuarioID}` para professores.
- `idnumber = matricula` para aluno, ou `{tenantId}:aluno:{matricula}` caso haja risco de colisao global.
- Antes de criar usuario, buscar por `username`.
- Se nao existir por `username`, buscar por `email` e `idnumber` para detectar conflitos.
- Atualizar dados basicos quando usuario ja existir.

### Professores

Funcoes provaveis:

- `core_user_get_users_by_field`
- `core_user_create_users`
- `core_user_update_users`
- `enrol_manual_enrol_users`

Regras recomendadas:

- Criar/atualizar usuario do professor.
- Matricular professor nos cursos correspondentes.
- Usar role Moodle configuravel:
  - `editingteacher` quando professor puder editar curso.
  - `teacher` quando nao puder editar.
- Nao fixar role id no codigo; usar configuracao.

### Estrutura academica

Funcoes provaveis:

- `core_course_create_categories`
- `core_course_update_categories`
- `core_course_create_courses`
- `core_course_update_courses`
- `core_course_get_courses_by_field`
- `core_cohort_create_cohorts`
- `core_cohort_update_cohorts`
- `core_group_create_groups`
- `core_group_get_course_groups`

Regras recomendadas:

- Categoria raiz por instituicao.
- Categoria por ano letivo.
- Categoria por grau/serie se fizer sentido operacional.
- Curso por turma + disciplina + ano.
- `course.idnumber = {tenantId}:{anoLetivo}:{turmaID}:{disciplinaID}`.
- Cohort por turma.
- `cohort.idnumber = {tenantId}:{anoLetivo}:turma:{turmaID}`.

### Matriculas

Funcoes provaveis:

- `enrol_manual_enrol_users`
- `enrol_manual_unenrol_users`
- `core_cohort_add_cohort_members`
- `core_cohort_delete_cohort_members`

Regras recomendadas:

- Matricular alunos ativos nos cursos de sua turma/disciplina.
- Suspender ou desmatricular alunos inativos conforme regra definida.
- Evitar remover matriculas manualmente criadas no Moodle sem ter certeza de que sao gerenciadas pela integracao.
- Registrar mapeamento entre aluno W3Escola, usuario Moodle, curso Moodle e matricula.

### Conteudos

Retornar `501 Not Implemented` inicialmente.

Motivo:

- Criar usuarios, cursos e matriculas e bem suportado pelos WebServices nativos.
- Publicar conteudos ricos, arquivos, paginas, tarefas, anexos e recursos de forma idempotente tende a ser mais complexo.
- Pode ser necessario criar um plugin local no Moodle para expor uma API mais adequada ao modelo do W3Escola.

Resposta recomendada:

```json
{
  "status": "not_implemented",
  "tipo": "conteudos",
  "mensagem": "Publicacao de conteudos no Moodle provavelmente exigira API interna, plugin local ou modelagem especifica de recursos/atividades."
}
```

### Notas

Retornar `501 Not Implemented` inicialmente.

Motivo:

- Antes de gravar ou importar notas, e preciso definir a fonte oficial.
- Se o W3Escola for fonte oficial, a API precisa mapear avaliacoes/campos de nota para itens do gradebook.
- Se o Moodle for fonte oficial para atividades online, a API precisa importar notas sem sobrescrever boletins escolares indevidamente.

Resposta recomendada:

```json
{
  "status": "not_implemented",
  "tipo": "notas",
  "mensagem": "Sincronizacao de notas depende da regra de fonte oficial, mapeamento de itens de nota e integracao especifica com o gradebook."
}
```

### Agenda

Retornar `501 Not Implemented` inicialmente.

Motivo:

- A agenda pode ser representada como eventos do calendario Moodle, atividades, eventos de curso ou eventos de grupo.
- E preciso decidir se a agenda oficial continua no W3Escola ou se parte dela passa a ser gerenciada pelo Moodle.

Resposta recomendada:

```json
{
  "status": "not_implemented",
  "tipo": "agenda",
  "mensagem": "Sincronizacao de agenda depende da decisao entre calendario Moodle, eventos por curso/grupo e origem oficial da agenda."
}
```

## Sincronizacao full

Na primeira versao, `full` deve chamar apenas os modulos suportados:

1. `usuarios`
2. `professores`
3. `estrutura-academica`
4. `matriculas`

Nao chamar automaticamente `conteudos`, `notas` e `agenda` enquanto elas retornarem `501`, para evitar que uma sincronizacao completa pare por funcionalidades ainda pendentes.

Exemplo:

```csharp
public async Task<RespostaSincronizacao> SincronizarFullAsync(string tenantId, CancellationToken cancellationToken)
{
    await SincronizarUsuariosAsync(tenantId, cancellationToken);
    await SincronizarProfessoresAsync(tenantId, cancellationToken);
    await SincronizarEstruturaAcademicaAsync(tenantId, cancellationToken);
    await SincronizarMatriculasAsync(tenantId, cancellationToken);

    return RespostaSincronizacao.Concluido(
        tenantId,
        "full",
        "Sincronizacao completa concluida para os modulos suportados nesta versao.",
        [
            "Conteudos, notas e agenda ainda nao fazem parte do full porque dependem de implementacao especifica."
        ]
    );
}
```

## Quando usar 200, 202 e 501

Para a primeira versao:

- Usar `200 OK` quando a sincronizacao roda na propria requisicao e termina antes da resposta.
- Usar `501 Not Implemented` para rotas expostas, mas ainda nao suportadas tecnicamente.

Para uma versao de producao:

- Usar `202 Accepted` para rotas demoradas.
- Retornar `jobId`.
- Criar endpoints:
  - `GET /api/instituicoes/{tenantId}/jobs/{jobId}`
  - `GET /api/instituicoes/{tenantId}/jobs`

Essa mudanca sera especialmente importante para `sync/full`, pois a sincronizacao completa pode passar do tempo adequado para uma requisicao HTTP.

## Idempotencia

As rotas devem ser idempotentes sempre que possivel:

- Repetir `sync/usuarios` nao deve duplicar usuarios.
- Repetir `sync/estrutura-academica` nao deve duplicar cursos/categorias.
- Repetir `sync/matriculas` nao deve criar matriculas duplicadas.
- Repetir `sync/professores` nao deve matricular o mesmo professor varias vezes.

Para isso, usar identificadores externos consistentes:

- Usuario aluno: `username = {tenantId}.aluno.{matricula}`.
- Usuario professor: `username = {tenantId}.prof.{usuarioID}`.
- Curso: `idnumber = {tenantId}:{anoLetivo}:{turmaID}:{disciplinaID}`.
- Cohort turma: `idnumber = {tenantId}:{anoLetivo}:turma:{turmaID}`.

## Ordem de implementacao sugerida

1. Criar `SincronizacaoController`.
2. Criar `RespostaSincronizacao`.
3. Criar `ISincronizadorMoodle` e `SincronizadorMoodle`.
4. Criar `IMoodleClient` e extrair a logica do exemplo C#.
5. Criar `IConfiguracaoMoodleTenant`.
6. Registrar dependencias no `Program.cs`.
7. Implementar `sync/usuarios` com uma fonte mock ou fonte real do W3Escola.
8. Implementar `sync/professores`.
9. Implementar `sync/estrutura-academica`.
10. Implementar `sync/matriculas`.
11. Manter `sync/conteudos`, `sync/notas` e `sync/agenda` retornando `501` ate fechar a estrategia.

## Observacoes importantes

- Nao colocar token Moodle em controller.
- Nao montar chamadas HTTP diretamente no controller.
- Nao espalhar nomes de `wsfunction` por toda a aplicacao; concentrar no `MoodleClient` ou em servicos especificos.
- Nao assumir role ids fixos do Moodle em codigo. Configurar `StudentRoleId`, `TeacherRoleId` e `EditingTeacherRoleId`.
- Registrar logs por tenant, tipo de sincronizacao e contadores.
- Tratar erros por item quando possivel, principalmente em sincronizacoes grandes.
- Evitar deletar/desmatricular dados no Moodle sem uma regra clara de propriedade da integracao.

## Resultado esperado da primeira entrega

Ao final da primeira entrega, a API deve:

- Expor todas as rotas de sincronizacao.
- Executar chamadas reais ao Moodle nas rotas suportadas.
- Retornar `501` em `conteudos`, `notas` e `agenda`.
- Manter controllers pequenos.
- Reaproveitar o comportamento validado do exemplo `moodle-api-client-csharp`.
- Estar pronta para evoluir para jobs assincronos sem precisar redesenhar tudo.
