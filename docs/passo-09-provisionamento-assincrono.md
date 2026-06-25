# Passo 9: Provisionamento assincrono simplificado

## Objetivo deste passo

Neste passo, o objetivo e simplificar o provisionamento de novas instituicoes sem perder seguranca operacional.

A ideia principal e:

```text
Antes:
  API .NET recebe requisicao
  API .NET altera arquivos
  API .NET sobe container diretamente
  API .NET tenta devolver sucesso na mesma requisicao

Depois:
  API .NET recebe requisicao
  API .NET valida dados
  API .NET grava uma solicitacao no banco
  Processador de provisionamento executa o trabalho em segundo plano
  Processador marca a instituicao como ativa somente depois do healthcheck
```

Essa e uma simplificacao intencional: ainda nao exige Kubernetes, Nomad, ECS, RabbitMQ ou Vault. O projeto pode continuar usando Docker Compose em um servidor unico, mas com um fluxo mais previsivel, auditavel e facil de recuperar quando algo falha.

## Convencao de nomes em portugues

Todos os nomes que voce implementar no service .NET, no banco, nos arquivos gerados e nos contratos da API podem seguir portugues Brasil.

Neste documento, a convencao recomendada e:

- usar `instituicao` no lugar de `tenant`;
- usar `tarefa` no lugar de `job`;
- usar `processador` no lugar de `worker`;
- usar `identificador_publico` no lugar de `slug` em banco e arquivos;
- usar `situacao` no lugar de `status` em entidades e respostas da API;
- usar nomes de tabelas, colunas, classes, propriedades e metodos em portugues.

Termos tecnicos da plataforma podem continuar em ingles quando forem nomes proprios ou comandos, como Docker Compose, Caddy, HTTP, healthcheck, endpoint, Redis, MariaDB e `BackgroundService`.

## O que voce vai aprender neste passo

Ao implementar este passo, voce vai praticar:

- separar requisicao HTTP de operacao de infraestrutura;
- criar um fluxo de provisionamento baseado em situacao;
- evitar que o endpoint publico execute Docker diretamente;
- registrar tarefas e eventos de provisionamento;
- validar identificador publico, nomes de banco, usuarios e containers;
- gerar arquivos por modelo;
- aplicar mudancas de forma idempotente;
- lidar com falhas parciais;
- ativar uma instituicao somente depois de healthcheck.

## Resultado esperado

Ao final deste passo, a criacao de uma instituicao tera este comportamento:

- a API responde rapido com `202 Accepted`;
- a instituicao nasce com situacao `Pendente`;
- uma tarefa de provisionamento e criada;
- um processador executa as etapas em segundo plano;
- cada etapa registra eventos;
- se tudo der certo, a instituicao vira `Ativa`;
- se algo falhar, a instituicao vira `Falhou` com motivo registrado;
- a mesma solicitacao pode ser reprocessada com seguranca.

## Por que esta simplificacao e melhor

Subir um container Moodle envolve varias etapas sensiveis:

- criar banco;
- criar usuario;
- gerar senha;
- criar arquivo de secret;
- criar volume;
- criar container;
- criar rota no proxy;
- executar healthcheck.

Se a API tentar fazer tudo isso dentro da propria requisicao HTTP, qualquer timeout, erro intermediario ou concorrencia pode deixar o ambiente em estado parcial.

Com provisionamento assincrono, a API apenas registra a intencao. O processador executa o trabalho com controle, logs, novas tentativas e estado persistido.

## Arquitetura simplificada

```text
Usuario/Admin
   |
   v
API .NET
   |
   | grava
   v
Banco da aplicacao
   |
   | consulta tarefas pendentes
   v
Processador de provisionamento
   |
   +--> MariaDB: cria banco e usuario
   +--> filesystem: cria secret e compose da instituicao
   +--> Docker: sobe container Moodle
   +--> Proxy: atualiza rota
   +--> Healthcheck: valida URL publica
```

Nesta versao simplificada, a fila pode ser o proprio banco da aplicacao. Isso reduz a quantidade de servicos novos e ja resolve o problema principal: tirar o provisionamento pesado do caminho da requisicao HTTP.

## Componentes recomendados

### API .NET

Responsabilidades:

- receber a solicitacao de criacao da instituicao;
- autenticar e autorizar o usuario;
- validar campos recebidos;
- gerar ou reservar o `identificador_publico`;
- criar o registro da instituicao com situacao `Pendente`;
- criar uma tarefa `ProvisionarInstituicao`;
- retornar `202 Accepted`.

A API nao deve:

- chamar `docker compose up`;
- escrever secrets diretamente;
- alterar o proxy diretamente;
- criar banco diretamente na mesma requisicao HTTP;
- montar ou acessar Docker socket se estiver exposta publicamente.

### Banco da aplicacao

Responsabilidades:

- guardar o cadastro das instituicoes;
- guardar as tarefas pendentes;
- guardar eventos de provisionamento;
- permitir novas tentativas;
- permitir auditoria.

### Processador de provisionamento

Responsabilidades:

- buscar tarefas pendentes;
- aplicar bloqueio na tarefa;
- executar etapas de provisionamento;
- registrar eventos;
- lidar com falhas;
- marcar a instituicao como `Ativa` ou `Falhou`.

O processador pode ser:

- um `BackgroundService` .NET rodando em um processo separado;
- um console app .NET executado por systemd;
- um container interno sem exposicao publica;
- no inicio, ate o mesmo projeto da API com uma variavel de ambiente separando os papeis.

Mesmo quando estiver no mesmo repositorio, o ideal e manter API e processador como papeis diferentes.

## Classes sugeridas

Os nomes abaixo seguem portugues Brasil e podem ser usados diretamente na implementacao .NET.

```text
Instituicao
TarefaProvisionamento
EventoProvisionamento
ServicoProvisionamentoInstituicao
ProcessadorProvisionamento
ServicoBancoInstituicao
ServicoArquivoSecret
ServicoComposeInstituicao
ServicoProxyInstituicao
ServicoHealthcheckInstituicao
PlanoProvisionamentoInstituicao
```

Exemplo de enums em portugues:

```csharp
public enum SituacaoInstituicao
{
    Pendente,
    EmProvisionamento,
    Ativa,
    Falhou,
    Suspensa,
    Excluindo,
    Excluida
}

public enum SituacaoTarefaProvisionamento
{
    NaFila,
    EmExecucao,
    Concluida,
    Falhou,
    AguardandoNovaTentativa,
    Cancelada
}
```

## Estados da instituicao

Estados recomendados:

```text
Pendente
EmProvisionamento
Ativa
Falhou
Suspensa
Excluindo
Excluida
```

Significado:

- `Pendente`: solicitacao criada, mas ainda nao processada.
- `EmProvisionamento`: processador esta criando recursos.
- `Ativa`: instituicao pronta e healthcheck aprovado.
- `Falhou`: provisionamento falhou e precisa de nova tentativa ou intervencao.
- `Suspensa`: instituicao existe, mas acesso foi suspenso.
- `Excluindo`: remocao em andamento.
- `Excluida`: recursos removidos ou arquivados.

## Estados da tarefa

Estados recomendados:

```text
NaFila
EmExecucao
Concluida
Falhou
AguardandoNovaTentativa
Cancelada
```

Campos importantes:

```text
tarefa_id
instituicao_id
tipo_tarefa
situacao
tentativas
maximo_tentativas
bloqueado_ate
ultimo_erro
criado_em
atualizado_em
```

## Tabelas sugeridas

### Tabela `instituicoes`

```sql
CREATE TABLE instituicoes (
  id CHAR(36) NOT NULL PRIMARY KEY,
  nome VARCHAR(200) NOT NULL,
  identificador_publico VARCHAR(80) NOT NULL UNIQUE,
  situacao VARCHAR(40) NOT NULL,
  url_publica VARCHAR(500) NOT NULL,
  nome_container VARCHAR(120) NOT NULL UNIQUE,
  nome_banco VARCHAR(120) NOT NULL UNIQUE,
  usuario_banco VARCHAR(120) NOT NULL UNIQUE,
  volume_moodledata VARCHAR(120) NOT NULL UNIQUE,
  prefixo_redis VARCHAR(120) NOT NULL UNIQUE,
  tag_imagem VARCHAR(120) NOT NULL,
  criado_em TIMESTAMP NOT NULL,
  atualizado_em TIMESTAMP NOT NULL
);
```

### Tabela `tarefas_provisionamento`

```sql
CREATE TABLE tarefas_provisionamento (
  id CHAR(36) NOT NULL PRIMARY KEY,
  instituicao_id CHAR(36) NOT NULL,
  tipo VARCHAR(80) NOT NULL,
  situacao VARCHAR(40) NOT NULL,
  tentativas INT NOT NULL DEFAULT 0,
  maximo_tentativas INT NOT NULL DEFAULT 3,
  bloqueado_ate TIMESTAMP NULL,
  ultimo_erro TEXT NULL,
  criado_em TIMESTAMP NOT NULL,
  atualizado_em TIMESTAMP NOT NULL
);
```

### Tabela `eventos_provisionamento`

```sql
CREATE TABLE eventos_provisionamento (
  id CHAR(36) NOT NULL PRIMARY KEY,
  instituicao_id CHAR(36) NOT NULL,
  tarefa_id CHAR(36) NOT NULL,
  etapa VARCHAR(120) NOT NULL,
  situacao VARCHAR(40) NOT NULL,
  mensagem TEXT NULL,
  criado_em TIMESTAMP NOT NULL
);
```

Essas tabelas sao uma base conceitual. Ajuste os tipos conforme o banco usado pela aplicacao .NET.

## Contrato da API

### Criar instituicao

Endpoint sugerido:

```text
POST /api/instituicoes
```

Exemplo de entrada:

```json
{
  "nome": "Escola Modelo",
  "identificadorPublicoSolicitado": "escola-modelo"
}
```

Exemplo de resposta:

```json
{
  "instituicaoId": "2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42",
  "situacao": "Pendente",
  "urlSituacao": "/api/instituicoes/2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42"
}
```

Status HTTP recomendado:

```text
202 Accepted
```

### Consultar situacao

Endpoint sugerido:

```text
GET /api/instituicoes/{id}
```

Exemplo de resposta durante provisionamento:

```json
{
  "instituicaoId": "2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42",
  "identificadorPublico": "escola-modelo",
  "situacao": "EmProvisionamento",
  "etapaAtual": "CriandoContainer"
}
```

Exemplo de resposta final:

```json
{
  "instituicaoId": "2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42",
  "identificadorPublico": "escola-modelo",
  "situacao": "Ativa",
  "urlPublica": "https://seudominio.com/i/escola-modelo"
}
```

## Validacao dos dados

O identificador publico deve ser seguro, previsivel e unico.

Regra recomendada:

```text
^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$
```

Exemplos validos:

```text
escola-a
colegio-modelo
instituto-2026
```

Exemplos invalidos:

```text
../escola
escola modelo
escola_modelo
EscolaA
admin
api
```

Regras importantes:

- gerar o identificador publico no servidor quando possivel;
- nao confiar cegamente no identificador publico enviado pelo cliente;
- impedir palavras reservadas;
- limitar tamanho;
- garantir unicidade;
- manter um `instituicao_id` interno imutavel;
- nunca usar input bruto em comandos shell.

## Nomes derivados da instituicao

A partir do identificador publico validado, o sistema pode gerar nomes padronizados.

Exemplo para identificador publico `escola-modelo`:

```text
instituicao_id:         2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42
identificador_publico:  escola-modelo
nome_container:         moodle_escola_modelo
nome_banco:             moodle_escola_modelo
usuario_banco:          moodle_escola_modelo
volume_moodledata:      moodledata_escola_modelo
prefixo_redis:          escola_modelo_
url_publica:            https://seudominio.com/i/escola-modelo
```

O identificador publico pode mudar no futuro por necessidade comercial. O `instituicao_id` nao deve mudar.

## Etapas do processador

O processador deve executar as etapas em ordem.

```text
1. BloquearTarefa
2. MarcarInstituicaoEmProvisionamento
3. ValidarPlanoInstituicao
4. GerarCredenciais
5. CriarBancoEUsuario
6. GravarArquivoSecret
7. GerarArquivoCompose
8. ValidarArquivoCompose
9. SubirContainerMoodle
10. GerarConfiguracaoProxy
11. RecarregarProxy
12. ExecutarHealthcheck
13. MarcarInstituicaoAtiva
```

Cada etapa deve registrar um evento em `eventos_provisionamento`.

## Idempotencia

Idempotencia significa que uma etapa pode rodar mais de uma vez sem quebrar o ambiente.

Exemplos:

- se o banco ja existe, validar se pertence a instituicao esperada;
- se o usuario ja existe, validar permissao e senha esperada;
- se o secret ja existe, nao gerar outra senha sem necessidade;
- se o container ja existe, validar imagem, env e volume;
- se a rota ja existe, validar se aponta para o container correto.

Isso e importante porque tarefas podem falhar e ser reprocessadas.

## Secrets no MVP simplificado

No MVP em servidor unico, os secrets podem continuar em arquivos locais, desde que endurecidos.

Regras:

- `secrets/` deve ter permissao `700`;
- arquivos `.env` devem ter permissao `600`;
- secrets reais nao devem entrar no Git;
- cada instituicao deve ter senha unica;
- o processador deve ser o unico processo com permissao de escrita;
- logs nunca devem imprimir valores sensiveis.

Exemplo de arquivo gerado:

```text
secrets/escola-modelo.env
```

Conteudo esperado:

```text
MOODLE_URL=https://seudominio.com/i/escola-modelo
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_modelo
MOODLE_DB_USER=moodle_escola_modelo
MOODLE_DB_PASSWORD=valor-gerado-pelo-processador
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola-modelo
MOODLE_TENANT_ID=2c9adf77-2c6f-4c0e-8fd8-9a5f2d4e4d42
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_modelo_
```

As variaveis do Moodle continuam usando os nomes esperados pelo `config.php` e pela imagem Docker. A convencao em portugues vale para o service .NET, banco da plataforma, arquivos gerados pelo provisionador e contratos internos.

## Compose por instituicao

Para simplificar o rollback e reduzir conflito entre requisicoes simultaneas, uma opcao melhor do que editar um unico `docker-compose.instituicoes.yml` gigante e gerar um Compose por instituicao.

Estrutura sugerida:

```text
gerado/
  instituicoes/
    escola-modelo/
      docker-compose.yml
```

Exemplo:

```yaml
services:
  moodle_escola_modelo:
    image: w3soft/moodle:2026.06.1-local
    container_name: moodle_escola_modelo
    restart: unless-stopped
    env_file:
      - ../../../secrets/escola-modelo.env
    volumes:
      - moodledata_escola_modelo:/var/www/moodledata
    networks:
      - moodle_net
    cpus: "1.0"
    mem_limit: 1.5g
    mem_reservation: 512m

volumes:
  moodledata_escola_modelo:
    name: moodledata_escola_modelo

networks:
  moodle_net:
    external: true
```

Com isso, o processador pode subir apenas a instituicao nova:

```sh
docker compose -f gerado/instituicoes/escola-modelo/docker-compose.yml up -d
```

Essa abordagem evita reprocessar todas as instituicoes a cada nova criacao.

## Proxy no MVP simplificado

No curto prazo, o processador pode gerar um arquivo de rotas a partir das instituicoes ativas.

Exemplo conceitual:

```text
gerado/proxy/Caddyfile.instituicoes
```

Cada instituicao ativa gera uma rota:

```text
handle_path /i/escola-modelo/* {
  reverse_proxy moodle_escola_modelo:80
}
```

Depois de gerar a configuracao:

```text
1. Validar configuracao do Caddy
2. Substituir arquivo de forma atomica
3. Recarregar proxy
4. Testar rota publica
```

Em uma etapa futura, vale avaliar Traefik com labels Docker ou Caddy com configuracao dinamica para reduzir ainda mais a necessidade de gerar arquivo de proxy.

## Healthcheck

A instituicao so deve virar `Ativa` depois de um healthcheck.

Validacoes minimas:

- container esta rodando;
- URL publica responde;
- status HTTP e aceitavel;
- resposta nao e erro do proxy;
- Moodle consegue carregar configuracao;
- logs recentes nao mostram erro fatal.

Exemplo conceitual:

```text
GET https://seudominio.com/i/escola-modelo/
```

Resultado esperado:

```text
HTTP 200, 302 ou outro status esperado para a instalacao inicial
```

## Nova tentativa e falha

Quando uma etapa falhar, o processador deve:

- registrar o erro;
- incrementar `tentativas`;
- marcar a tarefa como `AguardandoNovaTentativa` ou `Falhou`;
- manter a instituicao como `EmProvisionamento` ou `Falhou`;
- nao marcar como `Ativa`;
- permitir reprocessamento manual.

Falhas transientes:

- Docker demorou para iniciar;
- banco ainda nao ficou pronto;
- proxy demorou para recarregar;
- healthcheck falhou por timeout.

Falhas permanentes:

- identificador publico invalido;
- nome ja em uso;
- senha perdida ou divergente;
- arquivo YAML invalido;
- rota conflitante;
- permissao insuficiente.

## Bloqueio de provisionamento

O processador deve evitar duas execucoes simultaneas para a mesma instituicao.

Estrategias simples:

- coluna `bloqueado_ate` na tabela `tarefas_provisionamento`;
- bloqueio por `instituicao_id`;
- bloqueio global para etapas que alteram proxy;
- timeout para liberar tarefas travadas.

Regra pratica:

```text
Somente um processador pode processar uma tarefa de uma instituicao por vez.
Somente um processador pode recarregar o proxy por vez.
```

## Auditoria

Cada acao importante deve gerar evento.

Exemplos:

```text
ValidarPlanoInstituicao: OK
CriarBancoEUsuario: OK
GravarArquivoSecret: OK
GerarArquivoCompose: OK
ValidarArquivoCompose: OK
SubirContainerMoodle: OK
RecarregarProxy: OK
ExecutarHealthcheck: OK
MarcarInstituicaoAtiva: OK
```

Em falha:

```text
ExecutarHealthcheck: FALHOU: timeout after 60 seconds
```

Essa auditoria ajuda muito quando o provisionamento falha no meio do caminho.

## Checklist de implementacao

- Criar tabela `instituicoes`.
- Criar tabela `tarefas_provisionamento`.
- Criar tabela `eventos_provisionamento`.
- Criar endpoint `POST /api/instituicoes`.
- Criar endpoint `GET /api/instituicoes/{id}`.
- Validar identificador publico no servidor.
- Criar tarefa `ProvisionarInstituicao`.
- Implementar processador de provisionamento.
- Implementar bloqueio de tarefa.
- Gerar senha forte por instituicao.
- Criar banco e usuario por instituicao.
- Gerar arquivo `.env` com permissao `600`.
- Gerar Compose por instituicao.
- Validar Compose antes de aplicar.
- Subir container da instituicao.
- Gerar ou atualizar rotas do proxy.
- Validar proxy antes de recarregar.
- Executar healthcheck.
- Marcar instituicao como `Ativa`.
- Registrar eventos de todas as etapas.
- Implementar nova tentativa controlada.

## O que ainda nao precisa entrar neste passo

Para manter o passo simples, ainda nao e necessario implementar:

- Kubernetes;
- RabbitMQ;
- Vault;
- multi-regiao;
- autoscaling;
- deploy azul/verde;
- rotacao automatica completa de secrets;
- cobranca por instituicao;
- painel administrativo completo.

Esses itens podem entrar depois. O ganho principal agora e tirar a operacao pesada da requisicao HTTP e criar um fluxo controlado.

## Cuidados de seguranca

- A API publica nao deve ter acesso direto ao Docker socket.
- O processador deve rodar em ambiente restrito.
- O processador deve aceitar somente tarefas vindas do banco.
- O processador deve validar o plano antes de executar.
- O processador nao deve executar comandos montados com input bruto.
- Secrets nao devem aparecer em logs.
- Arquivos gerados devem ter permissao restrita.
- Rotas devem ser validadas antes de recarregar o proxy.

## Resumo da decisao

Esta simplificacao mantem o projeto facil de operar:

- continua usando Docker Compose;
- continua usando arquivos `.env` no MVP;
- nao exige fila externa;
- nao exige orquestrador novo;
- nao muda a arquitetura de um Moodle por instituicao.

Mas tambem remove o risco mais importante:

```text
O endpoint HTTP deixa de executar infraestrutura diretamente.
```

Com isso, o provisionamento fica mais seguro, mais previsivel e mais facil de auditar.
