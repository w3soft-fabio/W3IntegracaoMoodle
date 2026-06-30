# Plano de Integracao W3Escola com Moodle LMS

## 1. Resumo das funcionalidades encontradas nos projetos

A analise dos projetos `W3EscolaAdmin`, `W3EscolaApp` e `MoodleProvisioner.Api` indica que ja existe uma base consistente de gestao escolar, comunicacao e processos pedagogicos que pode ser conectada ao Moodle por meio de uma API .NET intermediaria.

No **W3EscolaAdmin**, foram encontradas funcionalidades administrativas e pedagogicas relacionadas a:

- Login administrativo e selecao de instituicao.
- Suporte multi-instituicao usando o padrao de banco `W3Escola{instituicaoID}`.
- Turmas, alunos por turma e componentes curriculares.
- Vinculo professor, turma e disciplina.
- Registro de aulas, tarefas de casa e conteudos pedagogicos.
- Registro de presenca/frequencia, inclusive por disciplina e multidisciplinar.
- Digitacao de notas por turma, disciplina, ano letivo, professor e campos configuraveis por unidade.
- Consulta de boletim.
- Gabarito online, incluindo questoes, respostas, bloqueio de aluno, correcao e salvamento de nota.
- Enquetes, perguntas, respostas e dashboards.
- Mensageiro entre escola, alunos e responsaveis.
- Diario infantil.
- Grade horaria.
- Secretaria, captura de foto de aluno e listagem de alunos/turmas.
- Direcao, vagas por turma e indicadores financeiros.

No **W3EscolaApp**, foram encontradas funcionalidades voltadas a alunos e responsaveis:

- Login de aluno/responsavel e selecao de instituicao.
- Selecao/troca de aluno vinculado ao responsavel.
- Dados do aluno com `matricula`, `cpf`, `nome`, `email`, `turmaID`, `turmaDescricao`, `anoLetivo` e status `ativo`.
- Agenda da turma por dia e por mes.
- Grade horaria por turma e dia.
- Boletim.
- Material de apoio por turma e professor.
- Gabarito online do aluno, com questoes, respostas, bloqueio e salvamento de nota.
- Enquetes disponiveis e envio de respostas.
- Mensageiro, grupos, historico e anexos.
- Diario infantil.
- Eventos anuais.
- Matricula online.
- Biblioteca, financeiro, cantina, documentos pendentes e aviso de falta.

Na **MoodleProvisioner.Api**, ja existe uma API .NET de provisionamento com:

- Endpoint `POST /api/instituicoes`.
- DTO de criacao de instituicao com `displayName`, `slug`, `tenantId`, `databasePassword`, `publicUrl`, `cpu`, `memoryLimit` e `memoryReservation`.
- Middleware de API key.
- Swagger configurado.
- Servicos de provisionamento de instituicao.
- Configuracao de container/imagem Moodle por instituicao.

Essa API deve evoluir de provisionadora de tenants Moodle para uma ponte de integracao academica entre os sistemas W3Escola e o Moodle.

## 2. Entidades escolares relevantes para integracao com o Moodle

As principais entidades que fazem sentido para sincronizacao sao:

- Instituicao/tenant.
- Ano letivo.
- Grau/serie.
- Turma.
- Componente curricular/disciplina.
- Professor.
- Aluno.
- Responsavel, pai, mae, responsavel financeiro e responsavel pedagogico.
- Vinculo professor-turma-disciplina.
- Matricula/vinculo aluno-turma.
- Curso Moodle.
- Cohort ou grupo Moodle.
- Material de apoio.
- Registro de aula.
- Tarefa de casa.
- Agenda/eventos.
- Frequencia/presenca.
- Nota escolar.
- Gabarito/quiz.
- Enquete.
- Mensagens/comunicacao.

Para a primeira versao, as entidades essenciais sao instituicao, aluno, professor, turma, disciplina, curso e matricula.

## 3. Recursos que podem ser enviados para o Moodle

Os dados do sistema escolar que podem ser enviados para o Moodle sao:

- **Usuarios**
  - Alunos ativos.
  - Professores.
  - Responsaveis, em fase posterior e somente se houver necessidade de acesso direto ao Moodle.

- **Estrutura academica**
  - Categorias por instituicao, ano letivo e grau/serie.
  - Cursos por turma-disciplina.
  - Cohorts por turma.
  - Grupos por turma quando necessario.

- **Matriculas**
  - Alunos matriculados nos cursos correspondentes.
  - Professores vinculados aos cursos em que lecionam.
  - Suspensao/desmatricula quando aluno ou professor sair do vinculo.

- **Conteudos pedagogicos**
  - Materiais de apoio.
  - Registros de aula publicados para alunos.
  - Tarefas de casa.
  - Arquivos/anexos.

- **Agenda**
  - Eventos escolares.
  - Atividades previstas por turma/disciplina.

- **Notas**
  - Notas consolidadas do W3Escola para o gradebook do Moodle quando o W3Escola for a fonte oficial.

- **Gabarito online**
  - Avaliacoes objetivas como quizzes Moodle em fase posterior.
  - Questoes, alternativas/respostas corretas, tentativas e nota final, desde que haja regra clara de equivalencia.

## 4. Recursos que podem ser consumidos do Moodle

Os dados do Moodle que podem ser consumidos pelas aplicacoes escolares sao:

- Cursos disponiveis para aluno/professor.
- Conteudos e arquivos publicados nos cursos.
- Atividades e tarefas.
- Entregas de atividades.
- Notas de atividades Moodle.
- Progresso/conclusao de atividades.
- Conclusao de curso.
- Tentativas de quiz.
- Melhor nota de quiz.
- Calendario de eventos.
- Participantes/matriculas efetivas.
- Status tecnico do tenant Moodle.

Esses dados podem ser exibidos nos apps escolares sem substituir imediatamente os fluxos existentes de boletim, mensageiro e agenda.

## 5. Mapeamento entre entidades do sistema escolar e entidades do Moodle

Mapeamento recomendado para a primeira versao:

| Sistema escolar | Moodle | Observacao |
| --- | --- | --- |
| Instituicao / `tenantId` | Site/container Moodle individual | Um container por instituicao. |
| Instituicao | Categoria raiz Moodle | Organiza todos os cursos da escola. |
| Ano letivo | Categoria ou cohort | Usado para separar ciclos anuais. |
| Grau/serie | Categoria intermediaria | Opcional, mas util para organizacao. |
| Turma | Cohort Moodle | Agrupa alunos da turma. |
| Turma | Grupo Moodle | Usar dentro de cursos compartilhados, se necessario. |
| Disciplina/componente curricular | Curso Moodle | Recomendado curso por turma-disciplina. |
| Turma + disciplina + ano | Curso Moodle | Padrao principal de integracao. |
| Aluno / matricula | Usuario Moodle | `idnumber = matricula`. |
| Professor / usuarioID | Usuario Moodle | `idnumber = usuarioID`. |
| Responsavel / CPF | Usuario Moodle opcional | Nao sincronizar em v1, salvo necessidade real. |
| Matricula ativa | Enrolment Moodle | Role `student`. |
| Vinculo professor-disciplina | Enrolment Moodle | Role `editingteacher` ou `teacher`. |
| Material de apoio | Recurso/arquivo Moodle | Pode exigir plugin local para escrita robusta. |
| Registro de aula/tarefa | Atividade, pagina ou assignment | Publicar somente quando visivel ao aluno. |
| Nota escolar | Gradebook Moodle | Integrar com regra de fonte oficial. |
| Gabarito online | Quiz Moodle | Fase posterior. |

Padrao recomendado de identificadores:

- Curso Moodle: `idnumber = {tenantId}:{anoLetivo}:{turmaID}:{disciplinaID}`.
- Usuario aluno: `username = {tenantId}.aluno.{matricula}`.
- Usuario professor: `username = {tenantId}.prof.{usuarioID}`.
- Cohort turma: `idnumber = {tenantId}:{anoLetivo}:turma:{turmaID}`.

## 6. Sugestao de endpoints para a API .NET

Endpoints sugeridos para evoluir a `MoodleProvisioner.Api`:

### Instituicoes e status

- `GET /api/instituicoes/{tenantId}/moodle/status`
- `GET /api/instituicoes/{tenantId}/moodle/site-info`

### Sincronizacao

- `POST /api/instituicoes/{tenantId}/sync/full`
- `POST /api/instituicoes/{tenantId}/sync/usuarios`
- `POST /api/instituicoes/{tenantId}/sync/estrutura-academica`
- `POST /api/instituicoes/{tenantId}/sync/matriculas`
- `POST /api/instituicoes/{tenantId}/sync/professores`
- `POST /api/instituicoes/{tenantId}/sync/conteudos`
- `POST /api/instituicoes/{tenantId}/sync/notas`
- `POST /api/instituicoes/{tenantId}/sync/agenda`

### Usuarios

- `PUT /api/instituicoes/{tenantId}/moodle/usuarios/alunos/{matricula}`
- `PUT /api/instituicoes/{tenantId}/moodle/usuarios/professores/{usuarioId}`
- `POST /api/instituicoes/{tenantId}/moodle/usuarios/batch`

### Cursos e matriculas

- `PUT /api/instituicoes/{tenantId}/moodle/cursos/{externalId}`
- `POST /api/instituicoes/{tenantId}/moodle/cursos/{courseId}/matriculas/sincronizar`
- `POST /api/instituicoes/{tenantId}/moodle/cursos/{courseId}/professores/sincronizar`
- `POST /api/instituicoes/{tenantId}/moodle/cohorts/turmas/sincronizar`

### Conteudos e atividades

- `POST /api/instituicoes/{tenantId}/moodle/conteudos/publicar`
- `GET /api/instituicoes/{tenantId}/moodle/cursos/{courseId}/conteudos`
- `POST /api/instituicoes/{tenantId}/moodle/agenda/sincronizar`

### Notas, progresso e atividades

- `GET /api/instituicoes/{tenantId}/moodle/alunos/{matricula}/notas`
- `GET /api/instituicoes/{tenantId}/moodle/alunos/{matricula}/progresso`
- `GET /api/instituicoes/{tenantId}/moodle/cursos/{courseId}/notas`
- `POST /api/instituicoes/{tenantId}/moodle/notas/importar`
- `POST /api/instituicoes/{tenantId}/moodle/notas/exportar`

### Jobs e mapeamentos

- `GET /api/instituicoes/{tenantId}/jobs/{jobId}`
- `GET /api/instituicoes/{tenantId}/jobs`
- `GET /api/instituicoes/{tenantId}/sync/mapeamentos`
- `GET /api/instituicoes/{tenantId}/sync/mapeamentos?tipo=usuario|curso|matricula`

## 7. WebServices do Moodle que provavelmente serao necessarios

O Moodle expoe funcoes WebService seguindo o padrao `{component}_{method}`, e a API pode chamar essas funcoes via REST/JSON.

Funcoes provaveis:

### Base

- `core_webservice_get_site_info`

### Usuarios

- `core_user_create_users`
- `core_user_update_users`
- `core_user_get_users_by_field`

### Cursos e categorias

- `core_course_create_categories`
- `core_course_update_categories`
- `core_course_create_courses`
- `core_course_update_courses`
- `core_course_get_courses_by_field`
- `core_course_get_contents`

### Matriculas

- `enrol_manual_enrol_users`
- `enrol_manual_unenrol_users`

### Cohorts e grupos

- `core_cohort_create_cohorts`
- `core_cohort_update_cohorts`
- `core_cohort_add_cohort_members`
- `core_cohort_delete_cohort_members`
- `core_group_create_groups`
- `core_group_add_group_members`
- `core_group_get_course_groups`

### Notas

- `core_grade_update_grades`
- `core_grades_get_grades`
- `gradereport_user_get_grade_items`

### Assignments

- `mod_assign_get_assignments`
- `mod_assign_get_submissions`
- `mod_assign_get_grades`
- `mod_assign_save_grades`

### Quizzes

- `mod_quiz_get_quizzes_by_courses`
- `mod_quiz_get_user_attempts`
- `mod_quiz_get_user_best_grade`
- `mod_quiz_get_attempt_review`
- `mod_quiz_process_attempt`

### Conclusao e progresso

- `core_completion_get_activities_completion_status`
- `core_completion_get_course_completion_status`

### Calendario

- `core_calendar_create_calendar_events`
- `core_calendar_get_calendar_events`

### Observacao importante

Para criar e alterar atividades Moodle completas, como assignments, resources, paginas e quizzes, os WebServices nativos podem nao ser suficientes para todos os casos. Recomenda-se prever um plugin local Moodle, por exemplo `local_w3sync`, para expor operacoes controladas e idempotentes de escrita de conteudo.

## 8. Fluxos recomendados de sincronizacao

### Fluxo 1: Provisionamento da instituicao

1. Criar tenant Moodle com `POST /api/instituicoes`.
2. Persistir URL publica, tenantId, token Moodle e metadados do container.
3. Validar disponibilidade do tenant.
4. Chamar `core_webservice_get_site_info`.
5. Registrar status inicial da instituicao.

### Fluxo 2: Carga inicial academica

1. Buscar instituicao, turmas, alunos, professores, disciplinas e vinculos no W3Escola.
2. Criar/atualizar usuarios Moodle.
3. Criar categorias Moodle por ano/grau.
4. Criar cursos por turma-disciplina.
5. Criar cohorts por turma.
6. Matricular alunos.
7. Matricular professores.
8. Persistir mapeamentos W3Escola/Moodle.

### Fluxo 3: Sincronizacao incremental

1. Executar job diario ou por acionamento manual.
2. Identificar alteracoes por checksum, data de atualizacao ou comparacao de payload.
3. Atualizar usuarios, cursos e matriculas.
4. Suspender usuarios/vinculos inativos em vez de excluir.
5. Registrar erros parciais por entidade.

### Fluxo 4: Publicacao pedagogica

1. Professor registra aula, tarefa ou material no Admin.
2. API verifica se o conteudo deve ser exibido ao aluno.
3. API localiza curso Moodle por turma/disciplina.
4. API publica conteudo no Moodle.
5. API grava mapeamento entre registro W3Escola e modulo Moodle.

### Fluxo 5: Consumo de dados do Moodle

1. App ou Admin solicita notas, atividades ou progresso.
2. API resolve `tenantId`, aluno e curso.
3. API consulta Moodle.
4. API normaliza resposta para o modelo escolar.
5. Aplicacao exibe dados sem acessar diretamente o container Moodle.

### Fluxo 6: Notas

Recomendacao inicial:

- W3Escola permanece fonte oficial de boletim e notas escolares.
- Moodle fornece notas de atividades LMS.
- Consolidacao bidirecional so deve ser ativada por tipo de avaliacao e com regra explicita de precedencia.

## 9. Riscos, cuidados tecnicos e recomendacoes de arquitetura

### Multi-instituicao

- Nunca confiar apenas em parametros de rota para acessar tenant.
- Resolver `tenantId` em uma tabela de configuracao interna.
- Cada instituicao deve ter URL, token, database/container e configuracoes isoladas.

### Autenticacao e autorizacao

- Manter API key atual para operacoes administrativas.
- Evoluir para JWT/escopos quando apps ou servicos internos consumirem endpoints academicos.
- Separar permissoes de provisionamento, sincronizacao, leitura e escrita.

### Idempotencia

- Toda escrita deve usar identificador externo estavel.
- Usar `idnumber` no Moodle para usuarios, cursos e cohorts.
- Aceitar `Idempotency-Key` em operacoes HTTP.
- Evitar duplicar usuarios/cursos por falha ou retry.

### Mapeamentos

Criar uma tabela ou repositorio de mapeamento com:

- `tenantId`
- `entityType`
- `externalId`
- `moodleId`
- `checksum`
- `lastSyncedAt`
- `syncStatus`
- `lastError`

### Jobs, filas e erros

- Sincronizacoes pesadas devem ser assicronas.
- Usar fila/background service.
- Registrar `jobId` e `correlationId`.
- Implementar retry exponencial.
- Criar dead-letter para falhas persistentes.
- Permitir reprocessamento por entidade.

### Logs e auditoria

- Logar entidade, tenant, operacao, status e tempo.
- Nao logar CPF completo, senha, token ou dados sensiveis.
- Gerar trilha de auditoria para criacao, atualizacao e suspensao.

### LGPD e dados sensiveis

- Sincronizar somente dados necessarios.
- Evitar enviar responsaveis ao Moodle na primeira fase.
- Mascarar CPF em logs.
- Definir politica de retencao de dados.

### Disponibilidade do container

- Antes de jobs grandes, validar saude do Moodle.
- Tratar timeout por instituicao.
- Nao bloquear todos os tenants por falha de uma escola.

### Escrita de conteudo no Moodle

- Criacao de atividades completas pode exigir plugin local.
- Evitar acoplamento fragil a estrutura interna do banco Moodle.
- Preferir WebServices oficiais ou plugin controlado.

### Arquitetura recomendada

Componentes sugeridos na API:

- `W3EscolarClient`
- `MoodleClient`
- `TenantResolver`
- `SyncOrchestrator`
- `MappingRepository`
- `JobRepository`
- `MoodleContentPublisher`
- `MoodleGradeImporter`
- `MoodleHealthService`

## 10. Prioridade de implementacao por fases

### Fase 0: Base tecnica

- Configuracao de tenants.
- Health check Moodle.
- Armazenamento seguro de token Moodle.
- Tabela de mapeamentos.
- Estrutura de jobs/logs.

### Fase 1: Identidade e estrutura academica

- Sincronizar alunos.
- Sincronizar professores.
- Criar categorias.
- Criar cursos por turma-disciplina.
- Criar cohorts por turma.
- Matricular alunos e professores.

### Fase 2: Leitura do Moodle para os apps

- Listar cursos do aluno/professor.
- Consultar conteudos.
- Consultar progresso.
- Consultar calendario Moodle.
- Consultar notas de atividades Moodle.

### Fase 3: Publicacao do W3Escola para o Moodle

- Publicar materiais de apoio.
- Publicar registros de aula visiveis ao aluno.
- Publicar tarefas de casa.
- Sincronizar agenda escolar.

### Fase 4: Avaliacoes e notas avancadas

- Integrar assignments.
- Integrar quizzes/gabarito online.
- Importar notas do Moodle.
- Exportar notas escolares para gradebook.
- Definir regras de precedencia por avaliacao.

### Fase 5: Experiencia completa e governanca

- SSO entre W3Escola e Moodle.
- Responsaveis no Moodle, se necessario.
- Dashboards de sincronizacao.
- Alertas operacionais.
- Auditoria avancada.
- Configuracoes por instituicao.

## Assumptions adotadas

- O Moodle sera acessado pela API .NET, nao diretamente pelos apps Flutter.
- O W3Escola continua sendo a fonte oficial de cadastro, matriculas, turmas, professores e boletim escolar.
- O Moodle sera a fonte oficial para progresso, entregas e notas de atividades LMS.
- O curso Moodle padrao sera criado por turma-disciplina-ano letivo.
- Responsaveis nao serao sincronizados para o Moodle na primeira fase.
- Exclusoes fisicas devem ser evitadas; preferir suspensao ou desmatricula.
- Para escrita robusta de conteudo e atividades, sera considerado um plugin local Moodle.
