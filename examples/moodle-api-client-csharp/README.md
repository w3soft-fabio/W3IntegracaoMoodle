# Cliente C# para API REST do Moodle

Exemplo em C#/.NET para consumir a API REST do Moodle da `escola-a`.

O cliente usa a URL publica da instituicao:

```text
http://localhost:8088/i/escola-a
```

## Preparar

```sh
cd examples/moodle-api-client-csharp
cp .env.example .env
```

Edite `.env` e informe o token REST gerado no Moodle:

```env
MOODLE_BASE_URL=http://localhost:8088/i/escola-a
MOODLE_WS_TOKEN=cole_o_token_gerado_no_moodle_aqui
MOODLE_DEFAULT_COURSE_ID=2
MOODLE_STUDENT_ROLE_ID=5
MOODLE_TEMP_PASSWORD=TempPassw0rd!2026
```

## Comandos

Validar o token:

```sh
dotnet run -- site-info
```

Listar cursos:

```sh
dotnet run -- list-courses
```

Listar usuarios ativos cadastrados no Moodle:

```sh
dotnet run -- list-users
```

Criar somente usuarios novos a partir do arquivo `students.mock.json`:

```sh
dotnet run -- create-users
```

Sincronizar alunos mockados no curso configurado:

```sh
dotnet run -- sync-students
```

O arquivo de entrada e `students.mock.json`. O comando `create-users` busca cada aluno por `username`, cria o usuario se ele ainda nao existir e nao faz matricula. A sincronizacao (`sync-students`) tambem cria usuarios novos quando necessario e solicita a matricula no curso definido por `MOODLE_DEFAULT_COURSE_ID`.

## Funcoes Moodle usadas

O servico externo do Moodle precisa permitir estas funcoes:

```text
core_webservice_get_site_info
core_course_get_courses
core_user_get_users
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

O token nao e impresso nos logs. Guarde `.env` apenas localmente.
