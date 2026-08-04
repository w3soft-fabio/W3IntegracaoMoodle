<?php

// Informa ao Moodle que este arquivo esta rodando via linha de comando.
// Muitas rotinas internas do Moodle verificam essa constante para permitir
// execucao fora do navegador.
define('CLI_SCRIPT', true);

// Carrega a configuracao principal do Moodle e bibliotecas usadas neste script.
// Depois do `config.php`, variaveis globais como `$CFG` e `$DB` ficam
// disponiveis. Em C#, pense nisso como inicializar o container/contexto da
// aplicacao antes de chamar servicos internos.
require_once(__DIR__ . '/../config.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/webservice/lib.php');

// Escreve logs padronizados no stdout. Como este script roda durante o startup
// do container, essas mensagens aparecem nos logs do Docker.
function bootstrap_log(string $message): void {
    fwrite(STDOUT, "[moodle-bootstrap] {$message}" . PHP_EOL);
}

// Escreve um erro no stderr e encerra o processo com codigo 1. O tipo `never`
// indica que a funcao nao retorna para o chamador.
function bootstrap_fail(string $message): never {
    fwrite(STDERR, "[moodle-bootstrap] ERROR: {$message}" . PHP_EOL);
    exit(1);
}

// Le uma variavel de ambiente obrigatoria. Se ela nao existir ou estiver vazia,
// o provisionamento para imediatamente com uma mensagem clara.
function env_required(string $name): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        bootstrap_fail("Missing required environment variable: {$name}");
    }

    return $value;
}

// Exige a declaracao da variavel, aceitando vazio somente para configuracoes
// nas quais vazio e um valor valido e intencional.
function env_defined(string $name): string {
    $value = getenv($name);

    if ($value === false) {
        bootstrap_fail("Missing required environment variable: {$name}");
    }

    return $value;
}

function env_bool_required(string $name): bool {
    $value = strtolower(trim(env_required($name)));
    if (in_array($value, ['1', 'true', 'yes', 'on'], true)) {
        return true;
    }

    if (in_array($value, ['0', 'false', 'no', 'off'], true)) {
        return false;
    }

    bootstrap_fail("Environment variable {$name} must be a boolean value.");
}

// Le uma variavel de ambiente opcional e devolve um valor padrao quando ela nao
// foi informada. Isso deixa o Docker/Compose sobrescrever configuracoes sem
// obrigar que todas sejam declaradas.
function env_default(string $name, string $default): string {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return $value;
}

// Converte uma variavel de ambiente para booleano. Valores como `1`, `true`,
// `yes` e `on` sao tratados como true; qualquer outro valor informado vira
// false. Se a variavel nao existir, usa o default recebido.
function env_bool(string $name, bool $default): bool {
    $value = getenv($name);

    if ($value === false || $value === '') {
        return $default;
    }

    return in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
}

// Transforma uma string CSV simples em array, removendo espacos e itens vazios.
// Exemplo: "a, b,,c" vira ["a", "b", "c"].
function split_csv(string $value): array {
    $items = array_map('trim', explode(',', $value));
    return array_values(array_filter($items, static fn(string $item): bool => $item !== ''));
}

// Resolve a lista de funcoes de webservice. Com `*`, expande para todas as
// funcoes externas disponiveis nesta instalacao do Moodle.
function resolve_ws_functions(string $value): array {
    global $DB;

    if (trim($value) === '*') {
        return $DB->get_fieldset_select(
            'external_functions',
            'name',
            '1 = 1 ORDER BY name ASC'
        );
    }

    return split_csv($value);
}

// Atualiza os dados publicos do site Moodle, como nome completo, nome curto,
// resumo, email de suporte e timezone padrao.
function update_site_identity(): void {
    global $DB;

    $fullname = env_required('MOODLE_SITE_FULLNAME');
    $shortname = env_required('MOODLE_SITE_SHORTNAME');
    $summary = env_defined('MOODLE_SITE_SUMMARY');
    $supportemail = env_required('MOODLE_SUPPORT_EMAIL');
    $timezone = env_required('MOODLE_ADMIN_TIMEZONE');

    $site = $DB->get_record('course', ['id' => SITEID], '*', MUST_EXIST);
    $changed = false;

    // No Moodle, o "site" tambem e representado como um registro especial na
    // tabela `course`. Este loop compara os campos desejados e atualiza apenas
    // quando ha diferenca, mantendo a operacao idempotente.
    foreach (['fullname' => $fullname, 'shortname' => $shortname, 'summary' => $summary] as $field => $value) {
        if ((string)$site->{$field} !== $value) {
            $site->{$field} = $value;
            $changed = true;
        }
    }

    if ($changed) {
        $site->timemodified = time();
        $DB->update_record('course', $site);
        bootstrap_log("Updated site identity.");
    } else {
        bootstrap_log("Site identity already up to date.");
    }

    // `set_config` grava configuracoes globais do Moodle na tabela de config.
    set_config('supportemail', $supportemail);
    set_config('timezone', $timezone);
}

// Persiste o database de origem autorizado para esta instituição. A API de
// provisionamento usa o mesmo vínculo para impedir que uma sincronização W3
// destinada a outra instituição seja aplicada neste Moodle.
function ensure_w3_database_settings(): void {
    $database = env_required('MOODLE_W3_DATABASE');

    if (!preg_match('/^[A-Za-z0-9_-]+$/', $database)) {
        bootstrap_fail('MOODLE_W3_DATABASE contains unsupported characters.');
    }

    set_config('w3database', $database, 'local_w3sync');
    bootstrap_log("W3 database configured: {$database}.");
}

// Exige autenticacao para acessar paginas do Moodle. Com esta configuracao, um
// visitante que abrir a pagina inicial e redirecionado pelo proprio Moodle para
// `login/index.php`, antes que a lista de cursos seja exibida.
function ensure_access_settings(): void {
    $forcelogin = env_bool_required('MOODLE_FORCE_LOGIN');

    set_config('forcelogin', $forcelogin ? '1' : '0');
    bootstrap_log('Force login is ' . ($forcelogin ? 'enabled.' : 'disabled.'));
}

// Define o idioma padrao global do site. A configuracao fica no banco, pois
// ela tambem e usada por instalacoes ja existentes, nao apenas no momento em
// que o instalador CLI e executado pela primeira vez. Por padrao, desabilita
// a deteccao do idioma do navegador para que um visitante com Chrome em ingles
// ainda receba a tela inicial em portugues.
function ensure_language_settings(): void {
    $language = env_required('MOODLE_DEFAULT_LANG');
    $autodetect = env_bool_required('MOODLE_AUTO_DETECT_LANG');

    set_config('lang', $language);
    set_config('autolang', $autodetect ? '1' : '0');
    bootstrap_log("Default site language configured: {$language}.");
    bootstrap_log('Browser language auto-detection is ' . ($autodetect ? 'enabled.' : 'disabled.'));
}

// Habilita o modulo BigBlueButton que acompanha o Moodle e, quando informadas,
// persiste as credenciais da API recebidas pelo env_file do tenant. A operacao
// roda em todo startup para corrigir tanto instalacoes novas quanto bancos que
// tenham o modulo oculto depois de uma atualizacao.
function ensure_bigbluebutton_settings(): void {
    $enabled = env_bool_required('MOODLE_BBB_ENABLED');
    $recordingdefault = env_bool_required('MOODLE_BBB_RECORDING_DEFAULT');

    if (!class_exists(\core\plugininfo\mod::class)) {
        bootstrap_fail('Moodle activity plugin manager is unavailable.');
    }

    try {
        $changed = \core\plugininfo\mod::enable_plugin('bigbluebuttonbn', $enabled ? 1 : 0);
    } catch (Throwable $exception) {
        bootstrap_fail('Could not configure the BigBlueButton activity module: ' . $exception->getMessage());
    }

    // O modulo continua disponivel para videoconferencias, mas novas
    // atividades nao permitem gravacao por padrao. A variavel de ambiente
    // possibilita uma excecao explicita por instituicao.
    set_config('bigbluebuttonbn_recording_default', $recordingdefault ? '1' : '0');
    bootstrap_log(
        'BigBlueButton recording is '
        . ($recordingdefault ? 'enabled' : 'disabled')
        . ' by default.'
    );

    if (!$enabled) {
        bootstrap_log('BigBlueButton activity module is disabled by MOODLE_BBB_ENABLED.');
        return;
    }

    bootstrap_log(
        $changed
            ? 'BigBlueButton activity module enabled.'
            : 'BigBlueButton activity module already enabled.'
    );

    $serverurl = trim(env_defined('MOODLE_BBB_SERVER_URL'));
    $sharedsecret = env_defined('MOODLE_BBB_SHARED_SECRET');

    // As duas credenciais formam um par. Aceitar somente uma delas deixaria o
    // seletor de atividades visivel, mas todas as chamadas da API falhariam.
    if (($serverurl === '') !== ($sharedsecret === '')) {
        bootstrap_fail(
            'MOODLE_BBB_SERVER_URL and MOODLE_BBB_SHARED_SECRET must be provided together.'
        );
    }

    // Mantem compatibilidade com tenants existentes enquanto as credenciais
    // ainda nao foram adicionadas ao arquivo .env. Assim que forem preenchidas,
    // o proximo startup aplica a configuracao automaticamente.
    if ($serverurl === '') {
        bootstrap_log(
            'BigBlueButton credentials not configured; set MOODLE_BBB_SERVER_URL '
            . 'and MOODLE_BBB_SHARED_SECRET in the tenant .env file.'
        );
        return;
    }

    $parsedurl = parse_url($serverurl);
    $scheme = strtolower((string)($parsedurl['scheme'] ?? ''));
    if (!filter_var($serverurl, FILTER_VALIDATE_URL) || !in_array($scheme, ['http', 'https'], true)) {
        bootstrap_fail('MOODLE_BBB_SERVER_URL must be a valid HTTP or HTTPS URL.');
    }

    // O endpoint retornado por `bbb-conf --secret` termina com barra. Normalizar
    // aqui evita URLs quebradas ao concatenar os caminhos da API.
    $serverurl = rtrim($serverurl, '/') . '/';

    $algorithm = strtoupper(trim(env_required('MOODLE_BBB_CHECKSUM_ALGORITHM')));
    $allowedalgorithms = ['SHA1', 'SHA256', 'SHA512'];
    if (!in_array($algorithm, $allowedalgorithms, true)) {
        bootstrap_fail(
            'MOODLE_BBB_CHECKSUM_ALGORITHM must be one of: ' . implode(', ', $allowedalgorithms) . '.'
        );
    }

    // Estes sao os nomes globais usados pelo mod_bigbluebuttonbn do Moodle 5.0.
    // O segredo nunca e incluido nos logs.
    set_config('bigbluebuttonbn_server_url', $serverurl);
    set_config('bigbluebuttonbn_shared_secret', $sharedsecret);
    set_config('bigbluebuttonbn_checksum_algorithm', $algorithm);

    bootstrap_log("BigBlueButton server configured: {$serverurl}");
    bootstrap_log("BigBlueButton checksum algorithm configured: {$algorithm}.");
}

// Configura o servidor de saida usado pelo Moodle para notificacoes, redefinicao
// de senha e demais mensagens usando somente valores explicitos do tenant.
function ensure_smtp_settings(): void {
    $host = trim(env_required('MOODLE_SMTP_HOST'));
    $authtype = strtoupper(trim(env_required('MOODLE_SMTP_AUTH_TYPE')));
    $username = env_required('MOODLE_SMTP_USER');
    $password = env_required('MOODLE_SMTP_PASSWORD');
    $security = strtolower(trim(env_defined('MOODLE_SMTP_SECURITY')));
    $noreplyaddress = trim(env_required('MOODLE_NOREPLY_ADDRESS'));

    if ($host === '') {
        bootstrap_fail('MOODLE_SMTP_HOST must not be empty.');
    }

    $allowedauthtypes = ['LOGIN', 'PLAIN', 'NTLM', 'CRAM-MD5'];
    if (!in_array($authtype, $allowedauthtypes, true)) {
        bootstrap_fail(
            'MOODLE_SMTP_AUTH_TYPE must be one of: ' . implode(', ', $allowedauthtypes) . '.'
        );
    }

    $allowedsecurity = ['', 'tls', 'ssl'];
    if (!in_array($security, $allowedsecurity, true)) {
        bootstrap_fail('MOODLE_SMTP_SECURITY must be empty, tls or ssl.');
    }

    if (!validate_email($noreplyaddress)) {
        bootstrap_fail('MOODLE_NOREPLY_ADDRESS must be a valid email address.');
    }

    set_config('smtphosts', $host);
    set_config('smtpauthtype', $authtype);
    set_config('smtpuser', $username);
    set_config('smtppass', $password);
    set_config('smtpsecure', $security);
    set_config('noreplyaddress', $noreplyaddress);

    // Usuario e senha nao sao incluidos nos logs para evitar vazamento das
    // credenciais do servidor de e-mail.
    bootstrap_log("SMTP server configured: {$host}");
    bootstrap_log("SMTP authentication configured: {$authtype} with {$security} security.");
    bootstrap_log("No-reply address configured: {$noreplyaddress}");
}

// Ajusta o perfil do usuario administrador criado pelo instalador do Moodle.
// Retorna o registro atualizado porque ele sera usado depois como criador do
// token de webservice.
function update_admin_user(bool $firstinstall): stdClass {
    global $DB;

    $username = env_required('MOODLE_ADMIN_USER');
    $admin = $DB->get_record('user', ['username' => $username, 'deleted' => 0], '*', MUST_EXIST);

    $user = (object)[
        'id' => $admin->id,
        'firstname' => env_required('MOODLE_ADMIN_FIRSTNAME'),
        'lastname' => env_required('MOODLE_ADMIN_LASTNAME'),
        'email' => env_required('MOODLE_ADMIN_EMAIL'),
        'city' => env_required('MOODLE_ADMIN_CITY'),
        'country' => env_required('MOODLE_ADMIN_COUNTRY'),
        'timezone' => env_required('MOODLE_ADMIN_TIMEZONE'),
    ];

    // Por seguranca, a senha do admin nao e redefinida em todo startup. Ela so
    // e enviada para `user_update_user` quando `MOODLE_ADMIN_RESET_PASSWORD`
    // estiver habilitado.
    $resetpassword = env_bool('MOODLE_ADMIN_RESET_PASSWORD', false);
    if ($resetpassword) {
        $user->password = env_required('MOODLE_ADMIN_PASSWORD');
    }

    user_update_user($user, $resetpassword, false);

    // Na primeira instalacao, pode forcar o admin a trocar a senha no primeiro
    // login. Isso evita que a senha inicial do ambiente fique em uso permanente.
    if ($firstinstall && env_bool_required('MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL')) {
        set_user_preference('auth_forcepasswordchange', 1, $admin->id);
        bootstrap_log("Admin password change will be required on first login.");
    }

    bootstrap_log("Admin user profile configured: {$username}.");
    return $DB->get_record('user', ['id' => $admin->id], '*', MUST_EXIST);
}

// Garante que webservices estejam habilitados no Moodle e que o protocolo REST
// esteja na lista de protocolos permitidos.
function ensure_webservice_settings(): void {
    global $CFG;

    set_config('enablewebservices', '1');
    $CFG->enablewebservices = '1';

    $protocols = empty($CFG->webserviceprotocols) ? [] : split_csv($CFG->webserviceprotocols);
    if (!in_array('rest', $protocols, true)) {
        // Atualiza tanto a config persistida quanto `$CFG` em memoria, porque o
        // restante deste mesmo processo pode consultar `$CFG` sem recarregar.
        $protocols[] = 'rest';
        set_config('webserviceprotocols', implode(',', $protocols));
        $CFG->webserviceprotocols = implode(',', $protocols);
        bootstrap_log("Enabled REST webservice protocol.");
    } else {
        bootstrap_log("REST webservice protocol already enabled.");
    }
}

// Garante que a inscricao manual usada pela API esteja habilitada e com todos
// os defaults necessarios para o Moodle criar uma instancia valida em cursos
// novos. Tambem repara cursos antigos criados enquanto enrol_manual/status nao
// existia na configuracao da imagem.
function ensure_manual_enrolment_settings(): void {
    global $DB;

    $enabled = env_bool_required('MOODLE_ENROL_MANUAL_ENABLED');
    $roleid = (int)env_required('MOODLE_ENROL_MANUAL_ROLE_ID');

    if ($roleid <= 0 || !$DB->record_exists('role', ['id' => $roleid])) {
        bootstrap_fail('MOODLE_ENROL_MANUAL_ROLE_ID must reference an existing Moodle role.');
    }

    if (!$enabled) {
        bootstrap_fail('Manual enrolment must remain enabled for W3 synchronization.');
    }

    try {
        \core\plugininfo\enrol::enable_plugin('manual', 1);
    } catch (Throwable $exception) {
        bootstrap_fail('Could not configure the manual enrolment plugin: ' . $exception->getMessage());
    }

    set_config('status', ENROL_INSTANCE_ENABLED, 'enrol_manual');
    set_config('roleid', $roleid, 'enrol_manual');
    set_config('enrolperiod', 0, 'enrol_manual');
    set_config('expirynotify', 0, 'enrol_manual');
    set_config('expirythreshold', 86400, 'enrol_manual');
    set_config('sendcoursewelcomemessage', 0, 'enrol_manual');

    $plugin = enrol_get_plugin('manual');
    if (!$plugin) {
        bootstrap_fail('Manual enrolment plugin is unavailable.');
    }

    $created = 0;
    $enabledinstances = 0;
    $courses = $DB->get_recordset_select('course', 'id <> :siteid', ['siteid' => SITEID], 'id ASC', 'id');
    foreach ($courses as $course) {
        $instance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual']);
        if (!$instance) {
            if (!$plugin->add_default_instance($course)) {
                bootstrap_fail("Could not create manual enrolment for course {$course->id}.");
            }
            $created++;
        } else if ((int)$instance->status !== ENROL_INSTANCE_ENABLED) {
            $plugin->update_status($instance, ENROL_INSTANCE_ENABLED);
            $enabledinstances++;
        }
    }
    $courses->close();

    bootstrap_log(
        "Manual enrolment configured; created {$created} and enabled {$enabledinstances} course instance(s)."
    );
}

// Cria ou atualiza o servico externo que agrupa as funcoes REST autorizadas
// para a integracao. No Moodle, um token pertence a um usuario e a um servico.
function ensure_service(array $functions): stdClass {
    global $DB;

    $manager = new webservice();
    $name = env_required('MOODLE_WS_SERVICE_NAME');
    $shortname = env_required('MOODLE_WS_SERVICE_SHORTNAME');

    // Falha cedo se alguma funcao REST configurada nao existir nesta instalacao.
    // Isso protege contra typos ou diferencas de versao/plugins do Moodle.
    foreach ($functions as $function) {
        if (!$DB->record_exists('external_functions', ['name' => $function])) {
            bootstrap_fail("External function does not exist in this Moodle installation: {$function}");
        }
    }

    $service = $manager->get_external_service_by_shortname($shortname);
    if (!$service) {
        // `restrictedusers = 1` significa que apenas usuarios explicitamente
        // autorizados poderao usar este servico externo.
        $service = (object)[
            'name' => $name,
            'enabled' => 1,
            'requiredcapability' => '',
            'restrictedusers' => 1,
            'component' => '',
            'shortname' => $shortname,
            'downloadfiles' => 0,
            'uploadfiles' => 0,
        ];
        $service->id = $manager->add_external_service($service);
        bootstrap_log("Created external service: {$shortname}.");
    } else {
        // Se o servico ja existe, o script o normaliza para o estado esperado.
        // Isso permite rodar o provisionamento varias vezes sem duplicar dados.
        $service->name = $name;
        $service->enabled = 1;
        $service->restrictedusers = 1;
        $service->requiredcapability = $service->requiredcapability ?? '';
        $service->downloadfiles = 0;
        $service->uploadfiles = 0;
        $manager->update_external_service($service);
        bootstrap_log("External service already exists: {$shortname}.");
    }

    // Vincula cada funcao REST ao servico, pulando as que ja estiverem ligadas.
    foreach ($functions as $function) {
        if (!$manager->service_function_exists($function, $service->id)) {
            $manager->add_external_function_to_service($function, $service->id);
            bootstrap_log("Added function to service: {$function}.");
        }
    }

    // Mantem o servico exatamente igual a allowlist configurada. Isso tambem
    // corrige uma instalacao parcial que tenha sido iniciada anteriormente com
    // `MOODLE_WS_FUNCTIONS=*`.
    $configuredfunctions = array_fill_keys($functions, true);
    $linkedfunctions = $DB->get_fieldset_select(
        'external_services_functions',
        'functionname',
        'externalserviceid = :serviceid',
        ['serviceid' => $service->id]
    );
    foreach ($linkedfunctions as $function) {
        if (!isset($configuredfunctions[$function])) {
            $manager->remove_external_function_from_service($function, $service->id);
            bootstrap_log("Removed function from service: {$function}.");
        }
    }

    return $manager->get_external_service_by_shortname($shortname, MUST_EXIST);
}

// Autoriza explicitamente o administrador a usar o servico externo criado.
// Isso e necessario porque o servico foi criado com `restrictedusers = 1`.
function authorize_service_user(stdClass $service, stdClass $admin): void {
    global $DB;

    $record = $DB->get_record('external_services_users', [
        'externalserviceid' => $service->id,
        'userid' => $admin->id,
    ]);

    if ($record) {
        bootstrap_log("Administrator already authorized for service.");
        return;
    }

    $DB->insert_record('external_services_users', (object)[
        'externalserviceid' => $service->id,
        'userid' => $admin->id,
        'iprestriction' => '',
        'validuntil' => 0,
        'timecreated' => time(),
    ]);
    bootstrap_log("Authorized administrator for service.");
}

// Busca um token permanente ainda valido para o par usuario/servico. Se nao
// existir, cria um novo token e retorna o valor que a aplicacao externa usara.
function ensure_token(stdClass $service, stdClass $admin): string {
    global $DB;

    $now = time();
    $token = $DB->get_record_sql(
        'SELECT *
           FROM {external_tokens}
          WHERE userid = :userid
            AND externalserviceid = :serviceid
            AND tokentype = :tokentype
            AND (validuntil IS NULL OR validuntil = 0 OR validuntil > :now)
       ORDER BY id ASC',
        [
            'userid' => $admin->id,
            'serviceid' => $service->id,
            'tokentype' => EXTERNAL_TOKEN_PERMANENT,
            'now' => $now,
        ],
        IGNORE_MULTIPLE
    );

    if ($token) {
        // Reutilizar token evita invalidar clientes que ja estao configurados
        // com um token anterior ainda valido.
        bootstrap_log("Reusing active webservice token for service/user.");
        return $token->token;
    }

    // Gera o token e define metadados exigidos pelo Moodle. O `creatorid` usa o
    // admin para deixar auditavel quem criou o token durante o bootstrap.
    $tokenvalue = md5(uniqid((string)random_int(0, PHP_INT_MAX), true));
    $validuntil = (int)env_default('MOODLE_WS_TOKEN_VALID_UNTIL', '0');

    $DB->insert_record('external_tokens', (object)[
        'token' => $tokenvalue,
        'privatetoken' => random_string(64),
        'tokentype' => EXTERNAL_TOKEN_PERMANENT,
        'userid' => $admin->id,
        'externalserviceid' => $service->id,
        'sid' => null,
        'contextid' => context_system::instance()->id,
        'creatorid' => $admin->id,
        'iprestriction' => env_default('MOODLE_WS_TOKEN_IP_RESTRICTION', ''),
        'validuntil' => $validuntil,
        'timecreated' => $now,
        'lastaccess' => null,
        'name' => env_default('MOODLE_WS_TOKEN_NAME', 'W3Soft bootstrap token'),
    ]);

    bootstrap_log("Created new webservice token for service/user.");
    return $tokenvalue;
}

// Persiste o token em um arquivo local para que outros processos/servicos do
// ambiente possam le-lo sem consultar diretamente o banco do Moodle.
function write_token_file(string $token): void {
    $tokenfile = env_required('MOODLE_WS_TOKEN_FILE');

    // Exige caminho absoluto para evitar gravar o token em um diretorio relativo
    // inesperado dependendo de onde o processo foi iniciado.
    if (!str_starts_with($tokenfile, '/')) {
        bootstrap_fail('MOODLE_WS_TOKEN_FILE must be an absolute path.');
    }

    $directory = dirname($tokenfile);
    if (!is_dir($directory) && !mkdir($directory, 0700, true) && !is_dir($directory)) {
        bootstrap_fail("Could not create token directory: {$directory}");
    }

    // Permissoes restritivas: somente o dono pode ler/escrever o diretorio e o
    // arquivo do token. Isso reduz exposicao de uma credencial sensivel.
    chmod($directory, 0700);

    if (file_put_contents($tokenfile, $token . PHP_EOL, LOCK_EX) === false) {
        bootstrap_fail("Could not write webservice token file: {$tokenfile}");
    }

    chmod($tokenfile, 0600);
    bootstrap_log("Webservice token persisted at: {$tokenfile}");
}
