using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

// O programa pode ser executado a partir de bin/Debug, bin/Release ou de outro diretorio.
// Por isso, antes de carregar arquivos locais como .env e students.mock.json, ele sobe na
// hierarquia de pastas ate encontrar o arquivo .csproj que identifica a raiz deste exemplo.
var projectDir = AppContext.BaseDirectory;
while (!File.Exists(Path.Combine(projectDir, "MoodleApiClientCSharp.csproj")))
{
    var parent = Directory.GetParent(projectDir);
    if (parent is null)
    {
        throw new InvalidOperationException("Nao foi possivel localizar o diretorio do projeto.");
    }

    projectDir = parent.FullName;
}

try
{
    // O primeiro argumento da linha de comando define a acao do cliente.
    // Quando nenhum argumento e informado, o programa mostra a ajuda em vez de executar
    // uma chamada HTTP sem intencao explicita.
    var command = args.Length > 0 ? args[0] : "help";
    if (command is "help" or "-h" or "--help")
    {
        PrintHelp();
        return;
    }

    // A configuracao centraliza URL, token, curso padrao e papeis do Moodle.
    // O HttpClient e compartilhado por todas as chamadas desta execucao.
    var config = MoodleConfig.Load(projectDir);
    using var httpClient = new HttpClient();
    var client = new MoodleClient(httpClient, config);

    // Cada comando chama uma rotina pequena e especifica. Isso deixa o metodo principal
    // responsavel apenas por orquestrar a execucao e tratar erros globais.
    switch (command)
    {
        case "site-info":
            await ShowSiteInfo(client, config);
            break;
        case "list-courses":
            await ListCourses(client);
            break;
        case "list-users":
            await ListUsers(client);
            break;
        case "create-users":
            await CreateUsersFromJson(client, projectDir);
            break;
        case "sync-students":
            await SyncStudents(client, config, projectDir);
            break;
        default:
            PrintHelp();
            Environment.ExitCode = 1;
            break;
    }
}
catch (Exception error)
{
    // Qualquer falha esperada ou inesperada e mostrada em stderr e sinalizada ao shell
    // com codigo de saida 1, facilitando uso em scripts/CI.
    Console.Error.WriteLine(error.Message);
    Environment.ExitCode = 1;
}

static async Task ShowSiteInfo(MoodleClient client, MoodleConfig config)
{
    // core_webservice_get_site_info e uma chamada simples para validar token, URL e
    // conectividade. Se ela falhar, o erro normalmente indica problema de configuracao.
    var siteInfo = await client.CallAsync<JsonElement>("core_webservice_get_site_info", [], HttpMethod.Get);

    Console.WriteLine("Conexao com Moodle validada.");
    Console.WriteLine($"URL base: {config.BaseUrl}");
    Console.WriteLine($"Site: {siteInfo.GetOptionalString("sitename") ?? "(sem nome retornado)"}");
    Console.WriteLine(
        $"Usuario do token: {siteInfo.GetOptionalString("username") ?? siteInfo.GetOptionalString("fullname") ?? "(nao informado)"}"
    );
    Console.WriteLine($"Versao Moodle: {siteInfo.GetOptionalString("release") ?? "(nao informada)"}");
}

static async Task ListCourses(MoodleClient client)
{
    // Recupera todos os cursos visiveis ao token informado. O Moodle retorna uma lista
    // com varios metadados; este exemplo modela e imprime apenas id, shortname e fullname.
    var courses = await client.CallAsync<List<MoodleCourse>>("core_course_get_courses", [], HttpMethod.Get);

    Console.WriteLine($"Cursos retornados: {courses.Count}");

    foreach (var course in courses)
    {
        Console.WriteLine($"{course.Id} | {course.ShortName} | {course.FullName}");
    }
}

static async Task ListUsers(MoodleClient client)
{
    // Lista usuarios ativos cadastrados no Moodle. A funcao core_user_get_users retorna
    // um objeto com users/warnings, entao o exemplo imprime apenas os campos principais.
    var users = await client.ListUsers();

    Console.WriteLine($"Usuarios retornados: {users.Count}");

    foreach (var user in users.OrderBy(user => user.Id))
    {
        Console.WriteLine(
            $"{user.Id} | {user.Username ?? "(sem username)"} | {user.FullName ?? "(sem nome)"} | {user.Email ?? "(sem email)"}"
        );
    }
}

static async Task CreateUsersFromJson(MoodleClient client, string projectDir)
{
    // Cria somente usuarios novos a partir do arquivo local. Diferente de sync-students,
    // esta rotina nao solicita matricula em curso.
    var students = await LoadStudents(projectDir);

    Console.WriteLine($"Criando usuarios novos a partir de students.mock.json ({students.Count} registros).");

    foreach (var student in students)
    {
        student.Validate();

        try
        {
            var existingUser = await client.FindExistingUser(student);
            if (existingUser is not null)
            {
                Console.WriteLine($"{student.Username}: usuario ja existe, id {existingUser.Id}.");
                continue;
            }

            var user = await client.CreateUser(student);
            Console.WriteLine($"{student.Username}: usuario criado, id {user.Id}.");
        }
        catch (Exception error)
        {
            throw new InvalidOperationException(
                $"Falha ao criar aluno {student.Username} ({student.Email}, idnumber {student.IdNumber}).\n{error.Message}",
                error
            );
        }
    }

    Console.WriteLine("Criacao de usuarios concluida.");
}

static async Task SyncStudents(MoodleClient client, MoodleConfig config, string projectDir)
{
    // O arquivo mock funciona como uma fonte local de alunos. Em uma integracao real,
    // essa lista poderia vir de outro sistema, banco de dados, fila ou API.
    var students = await LoadStudents(projectDir);

    Console.WriteLine($"Sincronizando {students.Count} alunos no curso {config.DefaultCourseId}.");

    foreach (var student in students)
    {
        // Valida antes de chamar o Moodle para evitar erros remotos previsiveis, como
        // campos vazios ou pais fora do formato esperado.
        student.Validate();

        MoodleUser user;
        string action;

        try
        {
            // A sincronizacao e idempotente pelo username: se o usuario ja existe com o
            // mesmo username, ele e reaproveitado. Conflitos por email/idnumber sao tratados
            // como erro para evitar vincular ou sobrescrever a pessoa errada.
            var existingUser = await client.FindExistingUser(student);
            user = existingUser ?? await client.CreateUser(student);
            action = existingUser is null ? "criado" : "existente";
        }
        catch (Exception error)
        {
            throw new InvalidOperationException(
                $"Falha ao sincronizar aluno {student.Username} ({student.Email}, idnumber {student.IdNumber}).\n{error.Message}",
                error
            );
        }

        // A matricula e solicitada mesmo quando o usuario ja existia. No Moodle, repetir
        // uma matricula existente tende a ser seguro ou retornar um erro descritivo,
        // dependendo da configuracao/versao.
        await client.EnrolUser(user.Id);

        Console.WriteLine(
            $"{student.Username}: usuario {action}, id {user.Id}, matricula solicitada no curso {config.DefaultCourseId}."
        );
    }

    Console.WriteLine("Sincronizacao concluida.");
}

static async Task<List<Student>> LoadStudents(string projectDir)
{
    var studentsPath = Path.Combine(projectDir, "students.mock.json");
    return JsonSerializer.Deserialize<List<Student>>(await File.ReadAllTextAsync(studentsPath), JsonOptions.Default)
        ?? throw new InvalidOperationException("Nao foi possivel ler students.mock.json.");
}

static void PrintHelp()
{
    // Lista os comandos suportados por este exemplo de CLI.
    Console.WriteLine("Uso:");
    Console.WriteLine("  dotnet run -- site-info");
    Console.WriteLine("  dotnet run -- list-courses");
    Console.WriteLine("  dotnet run -- list-users");
    Console.WriteLine("  dotnet run -- create-users");
    Console.WriteLine("  dotnet run -- sync-students");
}

// Representa as configuracoes necessarias para falar com a API REST do Moodle.
// Records sao usados aqui porque carregam dados imutaveis de forma concisa.
sealed record MoodleConfig(
    string BaseUrl,
    string Token,
    int DefaultCourseId,
    int StudentRoleId,
    string TemporaryPassword
)
{
    public static MoodleConfig Load(string projectDir)
    {
        // Primeiro carrega variaveis do .env local, se existir. Variaveis ja definidas
        // no ambiente do processo vencem o .env, permitindo sobrescrever valores sem
        // alterar arquivos versionados/localmente.
        LoadLocalEnv(Path.Combine(projectDir, ".env"));

        return new MoodleConfig(
            // A URL base fica sem barra final para que o endpoint seja montado de forma
            // consistente: {BaseUrl}/webservice/rest/server.php.
            RequiredEnv("MOODLE_BASE_URL").TrimEnd('/'),
            RequiredEnv("MOODLE_WS_TOKEN"),
            // Valores padrao comuns no Moodle: curso id 2 e papel de estudante id 5.
            // Ambos podem ser substituidos por variaveis de ambiente.
            IntegerEnv("MOODLE_DEFAULT_COURSE_ID", 2),
            IntegerEnv("MOODLE_STUDENT_ROLE_ID", 5),
            OptionalEnv("MOODLE_TEMP_PASSWORD", "TempPassw0rd!2026")
        );
    }

    static void LoadLocalEnv(string envPath)
    {
        if (!File.Exists(envPath))
        {
            // O .env e opcional: em ambientes de automacao, as variaveis podem vir direto
            // do sistema operacional ou do provedor de CI/CD.
            return;
        }

        foreach (var rawLine in File.ReadAllLines(envPath))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                // Ignora linhas vazias e comentarios para permitir documentar o .env.
                continue;
            }

            var separatorIndex = line.IndexOf('=');
            if (separatorIndex < 0)
            {
                // Linhas sem '=' nao sao pares chave/valor validos e sao ignoradas.
                continue;
            }

            var key = line[..separatorIndex].Trim();
            var value = ParseEnvValue(line[(separatorIndex + 1)..]);

            if (key.Length > 0 && Environment.GetEnvironmentVariable(key) is null)
            {
                // Nao sobrescreve variaveis ja existentes no ambiente. Isso e util para
                // manter segredos fora do arquivo .env em producao.
                Environment.SetEnvironmentVariable(key, value);
            }
        }
    }

    static string ParseEnvValue(string value)
    {
        var trimmed = value.Trim();
        if (
            (trimmed.StartsWith('"') && trimmed.EndsWith('"'))
            || (trimmed.StartsWith('\'') && trimmed.EndsWith('\''))
        )
        {
            // Permite valores escritos como CHAVE="valor" ou CHAVE='valor', removendo
            // apenas as aspas externas.
            return trimmed[1..^1];
        }

        return trimmed;
    }

    static string RequiredEnv(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value))
        {
            // Falha cedo quando uma configuracao essencial nao foi fornecida.
            throw new InvalidOperationException($"Variavel de ambiente obrigatoria ausente: {name}");
        }

        return value.Trim();
    }

    static string OptionalEnv(string name, string defaultValue)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? defaultValue : value.Trim();
    }

    static int IntegerEnv(string name, int defaultValue)
    {
        var rawValue = OptionalEnv(name, defaultValue.ToString());
        if (!int.TryParse(rawValue, out var value))
        {
            // Os ids do Moodle precisam ser numericos para compor os parametros da API.
            throw new InvalidOperationException($"Variavel {name} precisa ser um numero inteiro.");
        }

        return value;
    }
}

// Encapsula todos os detalhes de comunicacao com o endpoint REST do Moodle:
// montagem de parametros, envio HTTP, tratamento de erros e conversao JSON.
sealed class MoodleClient(HttpClient httpClient, MoodleConfig config)
{
    // Todos os webservices REST do Moodle sao chamados pelo mesmo endpoint; a funcao real
    // e indicada pelo parametro wsfunction enviado em cada requisicao.
    readonly string endpoint = $"{config.BaseUrl}/webservice/rest/server.php";

    public async Task<T> CallAsync<T>(string wsFunction, IEnumerable<KeyValuePair<string, string>> parameters, HttpMethod method)
    {
        // Parametros obrigatorios para qualquer chamada REST no Moodle:
        // - wstoken: autentica a chamada.
        // - wsfunction: escolhe a funcao do webservice.
        // - moodlewsrestformat=json: pede resposta em JSON.
        var requestParameters = new List<KeyValuePair<string, string>>
        {
            new("wstoken", config.Token),
            new("wsfunction", wsFunction),
            new("moodlewsrestformat", "json")
        };
        requestParameters.AddRange(parameters);

        using var request = BuildRequest(method, requestParameters);
        using var response = await httpClient.SendAsync(request);
        var responseText = await response.Content.ReadAsStringAsync();
        var contentType = response.Content.Headers.ContentType?.ToString() ?? "(nao informado)";

        JsonElement body;
        try
        {
            // A resposta e lida primeiro como JsonElement para permitir inspecionar erros
            // genericos do Moodle antes de desserializar para o tipo final T.
            body = JsonSerializer.Deserialize<JsonElement>(responseText, JsonOptions.Default);
        }
        catch (JsonException)
        {
            // Algumas falhas do Moodle podem vir como XML ou HTML, mesmo quando pedimos JSON.
            // O erro e normalizado para uma mensagem amigavel com status, tipo e trecho do corpo.
            var xmlError = ParseMoodleXmlError(responseText);
            throw new InvalidOperationException(
                BuildRequestError(wsFunction, method, response, contentType, xmlError ?? "O corpo nao e JSON valido.", responseText)
            );
        }

        // O Moodle pode retornar HTTP 200 contendo um objeto de erro. Por isso, o corpo
        // precisa ser verificado alem do status HTTP.
        var moodleError = ParseMoodleJsonError(body) ?? ParseMoodleXmlError(responseText);
        if (moodleError is not null)
        {
            throw new InvalidOperationException(
                BuildRequestError(wsFunction, method, response, contentType, moodleError, responseText)
            );
        }

        if (!response.IsSuccessStatusCode)
        {
            // Se nao houve erro estruturado do Moodle, ainda assim status HTTP fora de 2xx
            // precisa interromper a execucao.
            throw new InvalidOperationException(
                BuildRequestError(wsFunction, method, response, contentType, null, responseText)
            );
        }

        // Somente depois das validacoes o JSON e convertido para o tipo esperado pela
        // chamada, como List<MoodleCourse>, List<MoodleUser> ou JsonElement.
        return body.Deserialize<T>(JsonOptions.Default)
            ?? throw new InvalidOperationException($"Resposta vazia ao chamar {wsFunction}.");
    }

    async Task<MoodleUser?> GetUserByField(string field, string value)
    {
        // core_user_get_users_by_field aceita campos como username, email e idnumber.
        // A sintaxe values[0] segue o padrao de arrays em formularios aceito pelo Moodle.
        var users = await CallAsync<List<MoodleUser>>(
            "core_user_get_users_by_field",
            [
                new("field", field),
                new("values[0]", value)
            ],
            HttpMethod.Post
        );

        return users.FirstOrDefault();
    }

    public async Task<MoodleUser?> FindExistingUser(Student student)
    {
        // Username e o identificador principal desta sincronizacao.
        var userByUsername = await GetUserByField("username", student.Username);
        if (userByUsername is not null)
        {
            return userByUsername;
        }

        // Email duplicado com username diferente indica possivel conflito de identidade.
        var userByEmail = await GetUserByField("email", student.Email);
        if (userByEmail is not null)
        {
            throw new InvalidOperationException(
                $"Ja existe um usuario no Moodle com o email {student.Email}, mas com outro username."
            );
        }

        // idnumber costuma representar um identificador externo da instituicao/sistema.
        // Se ja estiver em uso, criar outro usuario poderia duplicar a mesma pessoa.
        var userByIdNumber = await GetUserByField("idnumber", student.IdNumber);
        if (userByIdNumber is not null)
        {
            throw new InvalidOperationException(
                $"Ja existe um usuario no Moodle com o idnumber {student.IdNumber}, mas com outro username."
            );
        }

        return null;
    }

    public async Task<List<MoodleUser>> ListUsers()
    {
        var response = await CallAsync<MoodleUsersResponse>(
            "core_user_get_users",
            [
                new("criteria[0][key]", "deleted"),
                new("criteria[0][value]", "0")
            ],
            HttpMethod.Post
        );

        return response.Users;
    }

    public async Task<MoodleUser> CreateUser(Student student)
    {
        // Envia um unico usuario usando a estrutura users[0][campo] exigida pela funcao
        // core_user_create_users. Para criar em lote, seriam usados users[1], users[2] etc.
        var users = await CallAsync<List<MoodleUser>>(
            "core_user_create_users",
            [
                new("users[0][username]", student.Username),
                new("users[0][password]", config.TemporaryPassword),
                new("users[0][auth]", "manual"),
                new("users[0][firstname]", student.FirstName),
                new("users[0][lastname]", student.LastName),
                new("users[0][email]", student.Email),
                new("users[0][idnumber]", student.IdNumber),
                new("users[0][city]", student.City),
                new("users[0][country]", student.Country)
            ],
            HttpMethod.Post
        );

        return users.FirstOrDefault()
            ?? throw new InvalidOperationException($"Moodle nao retornou o usuario criado para {student.Username}.");
    }

    public Task<JsonElement> EnrolUser(int userId)
    {
        // Matricula o usuario no curso padrao com o papel configurado para estudante.
        // A funcao normalmente retorna um corpo vazio/JSON simples, por isso JsonElement basta.
        return CallAsync<JsonElement>(
            "enrol_manual_enrol_users",
            [
                new("enrolments[0][roleid]", config.StudentRoleId.ToString()),
                new("enrolments[0][userid]", userId.ToString()),
                new("enrolments[0][courseid]", config.DefaultCourseId.ToString())
            ],
            HttpMethod.Post
        );
    }

    HttpRequestMessage BuildRequest(HttpMethod method, List<KeyValuePair<string, string>> parameters)
    {
        if (method == HttpMethod.Get)
        {
            // Para GET, os parametros sao enviados na query string com URL encoding para
            // preservar caracteres especiais em tokens, nomes ou valores.
            var queryString = string.Join(
                "&",
                parameters.Select(parameter =>
                    $"{WebUtility.UrlEncode(parameter.Key)}={WebUtility.UrlEncode(parameter.Value)}"
                )
            );

            return new HttpRequestMessage(HttpMethod.Get, $"{endpoint}?{queryString}");
        }

        // Para POST, o Moodle espera application/x-www-form-urlencoded, especialmente
        // para parametros aninhados como users[0][email] e enrolments[0][userid].
        return new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new FormUrlEncodedContent(parameters)
        };
    }

    static string? ParseMoodleJsonError(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object)
        {
            // Erros estruturados do Moodle em JSON sao objetos; listas ou valores simples
            // representam respostas normais para varias funcoes.
            return null;
        }

        var errorCode = body.GetOptionalString("errorcode");
        var exception = body.GetOptionalString("exception");
        var message = body.GetOptionalString("message");
        var debugInfo = body.GetOptionalString("debuginfo");

        if (errorCode is null && exception is null)
        {
            // Sem errorcode/exception, o objeto e tratado como resposta valida.
            return null;
        }

        // Monta uma mensagem compacta contendo somente os campos que vieram na resposta.
        return string.Join(
            " | ",
            new[]
            {
                errorCode is null ? null : $"codigo={errorCode}",
                exception is null ? null : $"exception={exception}",
                message is null ? null : $"mensagem={message}",
                debugInfo is null ? null : $"debug={debugInfo}"
            }.Where(item => item is not null)
        );
    }

    static string? ParseMoodleXmlError(string responseText)
    {
        if (!responseText.Contains("<EXCEPTION", StringComparison.OrdinalIgnoreCase))
        {
            // Evita gastar processamento com regex quando o corpo claramente nao parece
            // ser uma excecao XML do Moodle.
            return null;
        }

        // Algumas instalacoes retornam excecoes XML mesmo em chamadas REST. Este parser
        // simples extrai os campos mais uteis para diagnostico.
        return string.Join(
            " | ",
            new[]
            {
                ParseXmlTag(responseText, "ERRORCODE") is { } errorCode ? $"codigo={errorCode}" : null,
                ParseXmlTag(responseText, "MESSAGE") is { } message ? $"mensagem={message}" : null,
                ParseXmlTag(responseText, "DEBUGINFO") is { } debugInfo ? $"debug={debugInfo}" : null
            }.Where(item => item is not null)
        );
    }

    static string? ParseXmlTag(string xml, string tagName)
    {
        // Regex e suficiente aqui porque so precisamos de trechos pequenos e conhecidos
        // do XML de erro do Moodle, nao de um parser XML completo.
        var match = Regex.Match(
            xml,
            $@"<{tagName}>([\s\S]*?)</{tagName}>",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant
        );

        return match.Success ? CompactWhitespace(match.Groups[1].Value) : null;
    }

    static string BuildRequestError(
        string wsFunction,
        HttpMethod method,
        HttpResponseMessage response,
        string contentType,
        string? details,
        string responseText
    )
    {
        // Padroniza mensagens de erro para incluir contexto operacional suficiente:
        // funcao chamada, status HTTP, metodo, Content-Type, detalhes e amostra do corpo.
        return string.Join(
            Environment.NewLine,
            new[]
            {
                $"Erro ao chamar {wsFunction}.",
                $"HTTP status: {(int)response.StatusCode} {response.ReasonPhrase}".Trim(),
                $"Metodo: {method.Method}",
                $"Content-Type: {contentType}",
                details is null ? null : $"Detalhes: {details}",
                responseText.Length == 0 ? null : $"Corpo da resposta: {SummarizeResponseBody(responseText, contentType)}"
            }.Where(line => line is not null)
        );
    }

    static string SummarizeResponseBody(string responseText, string contentType)
    {
        // HTML e reduzido a texto antes da exibicao; JSON/XML/texto recebem apenas
        // compactacao de espacos. O tamanho maximo evita despejar respostas enormes.
        var preview = contentType.Contains("html", StringComparison.OrdinalIgnoreCase)
            ? StripHtml(responseText)
            : CompactWhitespace(responseText);

        return preview.Length <= 1200 ? preview : $"{preview[..1200]}...";
    }

    static string StripHtml(string value)
    {
        // Remove scripts, estilos e tags para que paginas de erro HTML fiquem legiveis
        // no terminal e nao poluam a mensagem com markup.
        var withoutScript = Regex.Replace(value, @"<script\b[^>]*>[\s\S]*?</script>", " ", RegexOptions.IgnoreCase);
        var withoutStyle = Regex.Replace(withoutScript, @"<style\b[^>]*>[\s\S]*?</style>", " ", RegexOptions.IgnoreCase);
        var withoutTags = Regex.Replace(withoutStyle, @"<[^>]+>", " ");

        return CompactWhitespace(withoutTags);
    }

    static string CompactWhitespace(string value)
    {
        // Normaliza quebras de linha, tabs e multiplos espacos para uma unica linha curta.
        return Regex.Replace(value, @"\s+", " ").Trim();
    }
}

// Modelo local de aluno lido de students.mock.json. Os nomes das propriedades usam
// PascalCase no C#, mas JsonOptions permite mapear de/para camelCase no JSON.
sealed record Student(
    string Username,
    string FirstName,
    string LastName,
    string Email,
    string IdNumber,
    string City,
    string Country
)
{
    public void Validate()
    {
        // Todos os campos sao obrigatorios porque a criacao de usuario no Moodle tambem
        // depende desses dados para identidade, contato e localizacao.
        Require(nameof(Username), Username);
        Require(nameof(FirstName), FirstName);
        Require(nameof(LastName), LastName);
        Require(nameof(Email), Email);
        Require(nameof(IdNumber), IdNumber);
        Require(nameof(City), City);
        Require(nameof(Country), Country);

        if (Country.Length != 2)
        {
            // O Moodle espera codigo ISO 3166-1 alpha-2, como BR, US ou PT.
            throw new InvalidOperationException($"Aluno {Username}: country precisa usar codigo ISO de 2 letras.");
        }
    }

    static void Require(string fieldName, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            // Mensagem aponta o arquivo de origem para facilitar correcao dos dados mockados.
            throw new InvalidOperationException($"Campo obrigatorio vazio no arquivo students.mock.json: {fieldName}.");
        }
    }
}

// Subconjunto do usuario retornado pelo Moodle. A criacao usa Id/Username, enquanto a
// listagem tambem exibe nome completo e email quando o Moodle disponibiliza esses campos.
sealed record MoodleUser(int Id, string? Username, string? FullName, string? Email);

// Resposta da funcao core_user_get_users. Warnings nao sao usados neste exemplo, mas o
// envelope precisa ser modelado para acessar a lista de usuarios.
sealed record MoodleUsersResponse(List<MoodleUser> Users);

// Subconjunto do curso retornado pelo Moodle para listagem simples no terminal.
sealed record MoodleCourse(int Id, string ShortName, string FullName);

static class JsonOptions
{
    // Opcoes compartilhadas em toda serializacao/desserializacao:
    // - camelCase combina com os arquivos JSON do exemplo.
    // - PropertyNameCaseInsensitive tolera diferencas de caixa vindas da API/arquivos.
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
}

static class JsonElementExtensions
{
    public static string? GetOptionalString(this JsonElement element, string propertyName)
    {
        // Helper para ler propriedades opcionais sem repetir TryGetProperty em cada uso.
        // Quando o valor nao e string, ToString() ainda permite exibir numeros/booleanos.
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        return property.ValueKind == JsonValueKind.String ? property.GetString() : property.ToString();
    }
}
