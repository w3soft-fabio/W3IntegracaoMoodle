# Passo 7: Integrar um cliente externo com a API REST do Moodle

## Objetivo deste passo

Neste passo, o objetivo e criar um exemplo simples e seguro de consumo da API REST do Moodle.

O cenario do laboratorio sera:

```text
Banco externo de alunos -> cliente Node.js -> API REST do Moodle escola-a
```

Para manter o teste pequeno e repetivel, o banco externo sera representado por um arquivo JSON com alunos ficticios.

O cliente usara a URL publica da instituicao `escola-a`:

```text
http://localhost:8088/i/escola-a
```

Isso e importante porque, neste projeto, cada Moodle de instituicao e acessado pelo proxy Caddy usando o caminho `/i/{slug}`.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- habilitar Web services no Moodle;
- habilitar o protocolo REST;
- criar um usuario dedicado para integracao;
- criar um servico externo limitado;
- adicionar funcoes especificas ao servico;
- gerar um token de acesso;
- guardar o token fora do codigo;
- consultar dados do Moodle via GET;
- criar usuarios e matriculas via POST;
- rodar uma sincronizacao idempotente simples.

## Referencias oficiais

A documentacao do Moodle descreve que o endpoint REST usa parametros como:

```text
wstoken
wsfunction
moodlewsrestformat=json
```

Referencias:

- https://docs.moodle.org/dev/Creating_a_web_service_client
- https://docs.moodle.org/405/en/Using_web_services
- https://docs.moodle.org/dev/Web_service_API_functions

## Resultado esperado

Ao final deste passo, voce tera:

- um servico externo chamado `w3soft_student_sync`;
- um usuario dedicado chamado `svc_integracao`;
- um token REST criado para esse usuario;
- um exemplo em `examples/moodle-api-client`;
- comandos para validar o token, listar cursos e sincronizar alunos mockados.

## Conceitos rapidos antes dos comandos

### O Moodle usa um endpoint unico para REST

As chamadas REST entram por:

```text
{MOODLE_BASE_URL}/webservice/rest/server.php
```

No laboratorio da escola A:

```text
http://localhost:8088/i/escola-a/webservice/rest/server.php
```

A acao executada e definida pelo parametro `wsfunction`.

Exemplos:

```text
core_webservice_get_site_info
core_course_get_courses
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

### Token nao e senha de usuario

O token e uma credencial da integracao.

Trate o token como segredo:

- nao versionar em Git;
- nao imprimir em logs;
- nao colar em documentacao;
- preferir validade limitada;
- restringir por IP quando possivel;
- revogar e recriar quando houver suspeita de vazamento.

### GET e POST no Moodle REST

O Moodle aceita parametros via GET e POST.

Neste exemplo:

- `site-info` e `list-courses` usam GET para facilitar a validacao;
- `sync-students` usa POST para operacoes com mais parametros e para evitar URLs longas.

Em producao, prefira POST para reduzir a chance de tokens aparecerem em historico, proxies e logs de URL.

## Pre-requisitos

Antes de iniciar este passo, conclua:

```text
docs/passo-03-infraestrutura-compartilhada.md
docs/passo-05-criar-servico-moodle-por-instituicao.md
```

Suba a infraestrutura e os Moodles de instituicao:

```sh
docker compose -f docker-compose.infra.yml up -d
docker compose -f docker-compose.instituicoes.yml up -d
```

Acesse a escola A:

```text
http://localhost:8088/i/escola-a
```

Confirme que o Moodle esta instalado e que voce consegue entrar como administrador.

## Etapa 1: Habilitar Web services

No Moodle da escola A, acesse como administrador:

```text
Administracao do site > Recursos avancados
```

Habilite:

```text
Web services
```

Salve as alteracoes.

## Etapa 2: Habilitar o protocolo REST

Acesse:

```text
Administracao do site > Servidor > Web services > Gerenciar protocolos
```

Habilite:

```text
REST protocol
```

Nao habilite protocolos que a integracao nao vai usar.

## Etapa 3: Criar o usuario dedicado

Crie um usuario somente para a integracao:

```text
username: svc_integracao
firstname: Servico
lastname: Integracao
email: svc_integracao@example.edu.br
```

Use uma senha forte e exclusiva.

Esse usuario nao deve ser usado por pessoas. Ele existe para emitir o token e auditar as chamadas da integracao.

## Etapa 4: Criar um papel dedicado para Web service

Acesse:

```text
Administracao do site > Usuarios > Permissoes > Definir papeis
```

Crie um papel, por exemplo:

```text
Nome curto: ws_student_sync
Nome: Web service - sincronizacao de alunos
```

Permita, no minimo:

```text
webservice/rest:use
```

Depois, ao adicionar funcoes ao servico externo, o Moodle exibira as capacidades exigidas por cada funcao. Conceda somente as capacidades necessarias para:

- consultar informacoes basicas do site;
- consultar cursos;
- consultar usuarios por campo;
- criar usuarios;
- matricular usuarios manualmente.

Evite usar administrador como usuario de integracao.

## Etapa 5: Criar o servico externo

Acesse:

```text
Administracao do site > Servidor > Web services > Servicos externos
```

Crie um novo servico:

```text
Nome: W3Soft Student Sync
Nome curto: w3soft_student_sync
Habilitado: Sim
Somente usuarios autorizados: Sim
```

Usar "Somente usuarios autorizados" reduz o risco de outro usuario conseguir usar o mesmo servico.

## Etapa 6: Adicionar funcoes ao servico

Adicione estas funcoes ao servico `w3soft_student_sync`:

```text
core_webservice_get_site_info
core_course_get_courses
core_course_get_courses_by_field
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

O exemplo Node usa diretamente:

```text
core_webservice_get_site_info
core_course_get_courses
core_user_get_users_by_field
core_user_create_users
enrol_manual_enrol_users
```

A funcao `core_course_get_courses_by_field` fica disponivel para evoluir o exemplo e localizar cursos por `shortname`, `idnumber` ou outro campo.

## Etapa 7: Autorizar o usuario no servico

Dentro do servico externo, abra:

```text
Usuarios autorizados
```

Adicione:

```text
svc_integracao
```

Se o Moodle indicar capacidades faltantes, volte ao papel `ws_student_sync` e ajuste somente o necessario.

## Etapa 8: Gerar o token

Acesse:

```text
Administracao do site > Servidor > Web services > Gerenciar tokens
```

Crie um token para:

```text
Usuario: svc_integracao
Servico: W3Soft Student Sync
```

Quando possivel, configure:

```text
Restricao de IP: IP do servidor da integracao
Valido ate: uma data futura controlada
```

Copie o token apenas para o arquivo `.env` local do cliente. Nao cole o token neste documento.

## Etapa 9: Preparar o cliente Node

Entre na pasta do exemplo:

```sh
cd examples/moodle-api-client
```

Crie o arquivo `.env` a partir do exemplo:

```sh
cp .env.example .env
```

Edite `.env`:

```env
MOODLE_BASE_URL=http://localhost:8088/i/escola-a
MOODLE_WS_TOKEN=cole_o_token_gerado_no_moodle_aqui
MOODLE_DEFAULT_COURSE_ID=2
MOODLE_STUDENT_ROLE_ID=5
MOODLE_TEMP_PASSWORD=TempPassw0rd!2026
```

Observacoes:

- `MOODLE_BASE_URL` deve apontar para a URL publica da instituicao;
- `MOODLE_WS_TOKEN` deve ser o token do servico externo;
- `MOODLE_DEFAULT_COURSE_ID` deve ser o curso de teste;
- `MOODLE_STUDENT_ROLE_ID=5` costuma ser o papel de estudante em instalacoes padrao;
- `MOODLE_TEMP_PASSWORD` e apenas para laboratorio.

Confirme o ID correto do papel em:

```text
Administracao do site > Usuarios > Permissoes > Definir papeis
```

## Etapa 10: Validar o token

Execute:

```sh
npm run site-info
```

Resultado esperado:

```text
Conexao com Moodle validada.
URL base: http://localhost:8088/i/escola-a
Site: ...
Usuario do token: svc_integracao
Versao Moodle: ...
```

O token nao deve aparecer na saida do comando.

## Etapa 11: Listar cursos

Execute:

```sh
npm run list-courses
```

Resultado esperado:

```text
Cursos retornados: ...
1 | ...
2 | ...
```

Escolha um curso de teste e ajuste `MOODLE_DEFAULT_COURSE_ID` no `.env`.

## Etapa 12: Sincronizar alunos mockados

O arquivo de entrada e:

```text
examples/moodle-api-client/students.mock.json
```

Execute:

```sh
npm run sync-students
```

O cliente vai:

1. buscar cada aluno por `username`;
2. criar o usuario se ele ainda nao existir;
3. matricular o usuario no curso configurado.

Resultado esperado:

```text
Sincronizando 3 alunos no curso 2.
ana.silva: usuario criado, id 10, matricula solicitada no curso 2.
bruno.santos: usuario criado, id 11, matricula solicitada no curso 2.
carla.oliveira: usuario criado, id 12, matricula solicitada no curso 2.
Sincronizacao concluida.
```

Rode novamente:

```sh
npm run sync-students
```

Na segunda execucao, os usuarios devem aparecer como existentes:

```text
ana.silva: usuario existente, id 10, matricula solicitada no curso 2.
```

Isso valida a repeticao segura do teste.

## Etapa 13: Testar falha segura sem token

Remova temporariamente `MOODLE_WS_TOKEN` do `.env` ou deixe vazio:

```env
MOODLE_WS_TOKEN=
```

Execute:

```sh
npm run site-info
```

Resultado esperado:

```text
Variavel de ambiente obrigatoria ausente: MOODLE_WS_TOKEN
```

Restaure o token no `.env` depois do teste.

## Estrutura criada

```text
examples/moodle-api-client/
  .env.example
  package.json
  students.mock.json
  src/
    config.js
    moodle-client.js
    site-info.js
    list-courses.js
    sync-students.js
```

## Como evoluir para um banco externo real

Quando o teste com JSON estiver funcionando, substitua a leitura de `students.mock.json` por um adaptador de leitura do banco externo.

Mantenha a separacao:

```text
Fonte externa -> normalizacao de alunos -> cliente Moodle
```

Regras recomendadas:

- ler o banco externo com usuario somente leitura;
- mapear um identificador externo estavel para `idnumber`;
- nao sobrescrever usuarios manualmente editados sem regra clara;
- manter logs sem dados sensiveis;
- separar tokens por instituicao;
- usar uma URL Moodle por instituicao.

Para uma nova instituicao, crie outro token e outro `.env` apontando para:

```text
http://localhost:8088/i/escola-b
```

Nao reutilize o token da escola A na escola B.

## Problemas comuns

### `webservicesserviceexception`

O usuario do token nao esta autorizado no servico, o servico esta desabilitado ou a funcao nao foi adicionada.

### `accessexception`

Falta capacidade no papel do usuario de integracao.

Revise as capacidades exigidas exibidas pelo Moodle na tela do servico externo.

### `invalidtoken`

O token esta incorreto, expirou, foi revogado ou esta bloqueado por restricao de IP.

### `invalidparameter`

Algum campo enviado nao bate com o formato esperado pela funcao.

Confira `students.mock.json`, `MOODLE_DEFAULT_COURSE_ID` e `MOODLE_STUDENT_ROLE_ID`.

### Erro 404 no endpoint REST

Confirme que `MOODLE_BASE_URL` inclui o prefixo da instituicao:

```text
http://localhost:8088/i/escola-a
```

Nao use apenas:

```text
http://localhost:8088
```
