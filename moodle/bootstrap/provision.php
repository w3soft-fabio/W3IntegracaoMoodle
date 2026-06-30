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

// Atualiza os dados publicos do site Moodle, como nome completo, nome curto,
// resumo, email de suporte e timezone padrao.
function update_site_identity(): void {
    global $DB;

    $fullname = env_required('MOODLE_SITE_FULLNAME');
    $shortname = env_required('MOODLE_SITE_SHORTNAME');
    $summary = env_default('MOODLE_SITE_SUMMARY', '');
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

// Ajusta o perfil do usuario administrador criado pelo instalador do Moodle.
// Retorna o registro atualizado porque ele sera usado depois como criador do
// token de webservice.
function update_admin_user(bool $firstinstall): stdClass {
    global $DB;

    $username = env_default('MOODLE_ADMIN_USER', 'admin');
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
    if ($firstinstall && env_bool('MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL', true)) {
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

// Cria ou atualiza o servico externo que agrupa as funcoes REST autorizadas
// para a integracao. No Moodle, um token pertence a um usuario e a um servico.
function ensure_service(array $functions): stdClass {
    global $DB;

    $manager = new webservice();
    $name = env_default('MOODLE_WS_SERVICE_NAME', 'W3Soft Student Sync');
    $shortname = env_default('MOODLE_WS_SERVICE_SHORTNAME', 'w3soft_student_sync');

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

    return $manager->get_external_service_by_shortname($shortname, MUST_EXIST);
}

// Cria ou atualiza o usuario tecnico que sera usado pela integracao REST. Esse
// usuario e separado do admin para seguir o principio de menor privilegio.
function ensure_ws_user(): stdClass {
    global $DB;

    $username = core_text::strtolower(env_required('MOODLE_WS_USER_USERNAME'));
    $password = env_required('MOODLE_WS_USER_PASSWORD');
    $existing = $DB->get_record('user', ['username' => $username, 'deleted' => 0]);

    $user = (object)[
        'username' => $username,
        'firstname' => env_required('MOODLE_WS_USER_FIRSTNAME'),
        'lastname' => env_required('MOODLE_WS_USER_LASTNAME'),
        'email' => env_required('MOODLE_WS_USER_EMAIL'),
        'city' => env_required('MOODLE_WS_USER_CITY'),
        'country' => env_required('MOODLE_WS_USER_COUNTRY'),
        'timezone' => env_required('MOODLE_WS_USER_TIMEZONE'),
        'auth' => 'manual',
        'confirmed' => 1,
        'mnethostid' => 1,
    ];

    if ($existing) {
        // Assim como no admin, a senha do usuario tecnico so muda quando a flag
        // explicita de reset estiver ativa.
        $user->id = $existing->id;
        $resetpassword = env_bool('MOODLE_WS_USER_RESET_PASSWORD', false);
        if ($resetpassword) {
            $user->password = $password;
        }
        user_update_user($user, $resetpassword, false);
        bootstrap_log("Technical webservice user already exists: {$username}.");
        return $DB->get_record('user', ['id' => $existing->id], '*', MUST_EXIST);
    }

    $user->password = $password;
    $userid = user_create_user($user, true, false);
    bootstrap_log("Created technical webservice user: {$username}.");
    return $DB->get_record('user', ['id' => $userid], '*', MUST_EXIST);
}

// Cria ou atualiza um papel do Moodle com as permissoes necessarias para o
// usuario tecnico operar a integracao REST.
function ensure_ws_role(stdClass $wsuser): int {
    global $DB;

    $shortname = env_default('MOODLE_WS_ROLE_SHORTNAME', 'w3soft_ws_integration');
    $name = env_default('MOODLE_WS_ROLE_NAME', 'W3Soft webservice integration');
    $description = 'Role managed by Moodle container bootstrap for REST integrations.';
    $systemcontext = context_system::instance();

    $role = $DB->get_record('role', ['shortname' => $shortname]);
    if ($role) {
        $role->name = $name;
        $role->description = $description;
        $DB->update_record('role', $role);
        $roleid = (int)$role->id;
        bootstrap_log("Webservice role already exists: {$shortname}.");
    } else {
        $roleid = create_role($name, $shortname, $description);
        bootstrap_log("Created webservice role: {$shortname}.");
    }

    // Limita o papel ao contexto de sistema. Ou seja, ele e atribuido no nivel
    // global do Moodle, nao dentro de um curso especifico.
    set_role_contextlevels($roleid, [CONTEXT_SYSTEM]);

    // Capacidades minimas para consultar/criar cursos, criar usuarios e
    // realizar matriculas manuais via webservice.
    $capabilities = [
        'webservice/rest:use',
        'moodle/webservice:createtoken',
        'moodle/course:view',
        'moodle/course:viewhiddencourses',
        'moodle/course:create',
        'moodle/course:update',
        'moodle/user:create',
        'moodle/user:viewdetails',
        'moodle/user:viewhiddendetails',
        'moodle/course:useremail',
        'moodle/user:update',
        'enrol/manual:enrol',
    ];

    $extra = env_default('MOODLE_WS_EXTRA_CAPABILITIES', '');
    if ($extra !== '') {
        // Permite adicionar capacidades sem alterar a imagem/container.
        $capabilities = array_merge($capabilities, split_csv($extra));
    }

    foreach (array_unique($capabilities) as $capability) {
        // Valida cada capability antes de atribuir. Isso evita gravar permissoes
        // inexistentes por erro de digitacao ou por plugin ausente.
        if (!get_capability_info($capability)) {
            bootstrap_fail("Capability does not exist in this Moodle installation: {$capability}");
        }
        assign_capability($capability, CAP_ALLOW, $roleid, $systemcontext->id, true);
    }

    // Atribui o papel ao usuario tecnico no contexto global, se ainda nao tiver
    // sido atribuido.
    if (!$DB->record_exists('role_assignments', [
        'roleid' => $roleid,
        'contextid' => $systemcontext->id,
        'userid' => $wsuser->id,
    ])) {
        role_assign($roleid, $wsuser->id, $systemcontext->id);
        bootstrap_log("Assigned webservice role to user: {$wsuser->username}.");
    }

    // Autoriza este papel a atribuir o papel alvo em matriculas. Por padrao, o
    // alvo e `student`, permitindo que a integracao matricule usuarios como
    // estudantes.
    $targetshortname = env_default('MOODLE_WS_ENROL_TARGET_ROLE_SHORTNAME', 'student');
    $targetrole = $DB->get_record('role', ['shortname' => $targetshortname], '*', MUST_EXIST);
    if (!$DB->record_exists('role_allow_assign', ['roleid' => $roleid, 'allowassign' => $targetrole->id])) {
        core_role_set_assign_allowed($roleid, $targetrole->id);
        bootstrap_log("Allowed webservice role to assign target role: {$targetshortname}.");
    }

    // Limpa caches de permissao para que as alteracoes fiquem visiveis ainda
    // neste processo e nas proximas requisicoes.
    accesslib_clear_all_caches(true);
    return $roleid;
}

// Autoriza explicitamente o usuario tecnico a usar o servico externo criado.
// Isso e necessario porque o servico foi criado com `restrictedusers = 1`.
function authorize_service_user(stdClass $service, stdClass $wsuser): void {
    global $DB;

    $record = $DB->get_record('external_services_users', [
        'externalserviceid' => $service->id,
        'userid' => $wsuser->id,
    ]);

    $iprestriction = env_default('MOODLE_WS_USER_IP_RESTRICTION', '');
    $validuntil = (int)env_default('MOODLE_WS_USER_VALID_UNTIL', '0');

    if ($record) {
        // Se a autorizacao ja existe, apenas sincroniza restricao de IP e
        // validade com as variaveis de ambiente atuais.
        $record->iprestriction = $iprestriction;
        $record->validuntil = $validuntil;
        $DB->update_record('external_services_users', $record);
        bootstrap_log("Technical user already authorized for service.");
        return;
    }

    $DB->insert_record('external_services_users', (object)[
        'externalserviceid' => $service->id,
        'userid' => $wsuser->id,
        'iprestriction' => $iprestriction,
        'validuntil' => $validuntil,
        'timecreated' => time(),
    ]);
    bootstrap_log("Authorized technical user for service.");
}

// Busca um token permanente ainda valido para o par usuario/servico. Se nao
// existir, cria um novo token e retorna o valor que a aplicacao externa usara.
function ensure_token(stdClass $service, stdClass $wsuser, stdClass $admin): string {
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
            'userid' => $wsuser->id,
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
        'userid' => $wsuser->id,
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
    $tokenfile = env_default('MOODLE_WS_TOKEN_FILE', '/var/www/moodledata/w3soft/ws-token.txt');

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

// A partir daqui comeca a execucao real do script. As funcoes acima foram
// definidas primeiro para deixar o fluxo principal curto e legivel.
$firstinstall = env_bool('MOODLE_BOOTSTRAP_FIRST_INSTALL', false);

bootstrap_log('Starting tenant provisioning.');
update_site_identity();
$admin = update_admin_user($firstinstall);
ensure_webservice_settings();
// Lista de funcoes REST que farao parte do servico externo. Pode vir do
// ambiente ou cair no conjunto padrao usado pela integracao.
$functions = split_csv(env_default('MOODLE_WS_FUNCTIONS', 'core_webservice_get_site_info,core_course_get_courses,core_course_get_courses_by_field,core_course_create_courses,core_course_update_courses,core_user_get_users_by_field,core_user_create_users,enrol_manual_enrol_users'));
$service = ensure_service($functions);
$wsuser = ensure_ws_user();
ensure_ws_role($wsuser);
authorize_service_user($service, $wsuser);
$token = ensure_token($service, $wsuser, $admin);
write_token_file($token);
bootstrap_log('Tenant provisioning finished.');
