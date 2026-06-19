# Riscos e solucoes para producao

## Objetivo

Este documento registra os principais problemas encontrados na abordagem atual de provisionamento de instituicoes Moodle e propoe solucoes para evoluir o projeto de um laboratorio local para um ambiente de producao.

A arquitetura atual segue uma boa direcao conceitual:

- 1 container Moodle por instituicao;
- 1 banco logico por instituicao;
- 1 usuario de banco por instituicao;
- 1 volume `moodledata` por instituicao;
- 1 prefixo Redis por instituicao;
- 1 proxy reverso compartilhado;
- 1 infraestrutura compartilhada de banco, Redis e proxy.

O principal risco nao esta nessa separacao por instituicao. O principal risco esta em como os arquivos, secrets, rotas e containers sao criados e gerenciados.

## Estado atual observado

O projeto usa arquivos `.env` dentro de `secrets/` para alimentar variaveis de ambiente dos containers Moodle.

Exemplos de variaveis por instituicao:

```text
MOODLE_URL
MOODLE_DB_HOST
MOODLE_DB_NAME
MOODLE_DB_USER
MOODLE_DB_PASSWORD
MOODLE_DATAROOT
MOODLE_PUBLIC_SLUG
MOODLE_TENANT_ID
MOODLE_REDIS_HOST
MOODLE_REDIS_PORT
MOODLE_REDIS_PREFIX
```

O arquivo `docker-compose.instituicoes.yml` declara manualmente um servico por instituicao, apontando cada servico para um arquivo `.env` especifico.

O arquivo `proxy/Caddyfile.local` tambem possui rotas declaradas manualmente para cada instituicao.

A pasta `secrets/` esta ignorada pelo Git por meio de `secrets/*.env`, o que e positivo. Mesmo assim, arquivos locais de secrets continuam exigindo cuidado em producao.

## Problema 1: secrets em arquivos `.env`

### Risco

Arquivos `.env` sao simples e funcionam bem em desenvolvimento, mas nao devem ser tratados como cofre de secrets em producao.

Mesmo fora do Git, esses arquivos podem vazar por:

- permissoes incorretas no sistema de arquivos;
- backup do servidor;
- copia manual para suporte;
- logs acidentais;
- acesso de outro usuario local;
- comandos de diagnostico;
- `docker inspect`;
- variaveis expostas dentro do ambiente do processo no container.

No estado atual, alguns arquivos por instituicao estavam com permissao `rw-r--r--`, permitindo leitura por outros usuarios locais do sistema.

### Solucoes propostas

Para um primeiro endurecimento em servidor unico:

- manter `secrets/*.env` fora do Git;
- ajustar permissoes para `600`;
- garantir dono correto dos arquivos;
- restringir acesso SSH ao servidor;
- evitar imprimir variaveis de ambiente em logs;
- nunca versionar `.env` reais;
- criar arquivos `.env.example` sem valores sensiveis.

Exemplo:

```sh
chmod 700 secrets
chmod 600 secrets/*.env
```

Para uma producao mais robusta:

- usar Docker secrets, se estiver em Docker Swarm;
- usar Kubernetes Secrets, se migrar para Kubernetes;
- usar HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault ou ferramenta equivalente;
- usar SOPS com chaves KMS/age para secrets versionados criptografados;
- implementar rotacao de senhas por instituicao.

## Problema 2: service .NET com permissao para criar containers

### Risco

O service .NET que recebe a requisicao de criacao de instituicao passa a ser um componente critico da infraestrutura.

Se esse service puder escrever arquivos de Compose, alterar secrets, modificar proxy e chamar Docker, ele se torna um control plane. Caso seja comprometido, um atacante poderia:

- criar containers maliciosos;
- alterar rotas do proxy;
- acessar ou substituir secrets;
- apontar uma instituicao para banco de outra;
- causar indisponibilidade;
- tentar acesso ao Docker socket;
- escalar privilegios no host.

Em muitos ambientes, acesso ao Docker socket equivale a acesso root no servidor. Esse e um dos pontos mais sensiveis da arquitetura.

### Solucoes propostas

Separar a API publica do executor de infraestrutura.

Modelo recomendado:

```text
API .NET
  recebe requisicao
  valida dados
  grava solicitacao no banco
  publica job em fila

Worker de provisionamento
  consome job
  cria banco e usuario
  cria secrets
  cria ou atualiza servico
  atualiza proxy
  executa healthcheck
  marca instituicao como ativa
```

Recomendacoes:

- nao expor o worker de provisionamento na internet;
- proteger endpoints administrativos com autenticacao forte;
- aplicar autorizacao por perfil;
- registrar auditoria de toda acao;
- limitar os comandos que o worker pode executar;
- evitar montar o Docker socket em servicos publicos;
- rodar o provisionador em rede administrativa;
- usar fila para evitar concorrencia e permitir retry.

## Problema 3: edicao manual ou dinamica de arquivos Compose

### Risco

Adicionar uma instituicao alterando diretamente `docker-compose.instituicoes.yml` funciona em laboratorio, mas em producao pode gerar falhas como:

- duas requisicoes simultaneas sobrescrevendo o mesmo arquivo;
- arquivo YAML invalido;
- deploy parcial;
- servico criado sem rota;
- rota criada sem servico saudavel;
- dificil rollback;
- historico operacional fraco;
- baixa auditabilidade;
- estado real diferente do estado esperado.

### Solucoes propostas

Em servidor unico com Docker Compose:

- gerar arquivos a partir de templates;
- usar escrita atomica;
- validar YAML antes de aplicar;
- usar lock global de provisionamento;
- criar backup do arquivo anterior;
- aplicar mudancas somente apos validacao;
- executar healthcheck depois do deploy;
- registrar status `Pending`, `Provisioning`, `Active`, `Failed`.

Em arquitetura mais robusta:

- migrar para Kubernetes, Nomad, ECS ou outro orquestrador;
- representar cada instituicao como recurso declarativo;
- usar deploy automatizado com rollback;
- usar ingress/service discovery dinamico;
- evitar editar arquivos compartilhados manualmente.

## Problema 4: proxy com rotas estaticas por instituicao

### Risco

O `Caddyfile` local contem rotas especificas para cada escola.

Esse modelo escala mal porque cada nova instituicao exige:

- alterar arquivo do proxy;
- recarregar ou recriar o proxy;
- garantir que a rota nao conflita com outra;
- garantir que o container de destino existe;
- tratar rollback se o container nao subir.

### Solucoes propostas

Para curto prazo:

- gerar o `Caddyfile` por template;
- validar a configuracao antes de recarregar;
- aplicar reload sem derrubar conexoes quando possivel;
- manter mapa de slug para container no banco do provisionador;
- validar unicidade do slug.

Para medio/longo prazo:

- usar Traefik com labels Docker;
- usar Caddy com configuracao dinamica;
- usar Nginx com templates e reload controlado;
- usar Kubernetes Ingress;
- preferir subdominios por instituicao se a operacao permitir.

Exemplo de rota desejada:

```text
https://seudominio.com/i/escola-a -> moodle_escola_a
```

O slug publico deve ser validado e unico. O ID interno da instituicao deve ser imutavel e nao depender do slug.

## Problema 5: ausencia de fluxo transacional de provisionamento

### Risco

Criar uma instituicao envolve varias etapas:

- validar dados recebidos;
- gerar slug;
- gerar credenciais;
- criar banco;
- criar usuario;
- conceder permissoes;
- criar arquivo de secret;
- criar volume;
- criar container;
- criar rota no proxy;
- executar instalacao/configuracao inicial;
- executar healthcheck;
- liberar acesso.

Se qualquer etapa falhar no meio, o sistema pode ficar em estado parcial.

Exemplos:

- banco criado, mas container nao criado;
- secret criado com senha diferente da senha do banco;
- rota criada apontando para container inexistente;
- container ativo apontando para banco errado;
- instituicao marcada como pronta sem healthcheck.

### Solucoes propostas

Implementar provisionamento idempotente e orientado a estado.

Estados recomendados:

```text
Pending
Provisioning
Active
Failed
Suspended
Deleting
Deleted
```

Cada etapa deve poder ser repetida com seguranca.

Boas praticas:

- usar uma tabela de instituicoes;
- usar uma tabela de eventos de provisionamento;
- salvar o plano esperado antes de aplicar;
- usar locks por slug e por tenant;
- validar pre-condicoes antes de cada etapa;
- executar compensacao quando possivel;
- nunca liberar a instituicao antes do healthcheck final.

## Problema 6: validacao insuficiente de dados de entrada

### Risco

O service .NET recebe informacoes da instituicao. Se esses dados forem usados para criar nomes de arquivos, containers, bancos, usuarios, volumes ou rotas, existe risco de:

- path traversal;
- command injection;
- nomes invalidos de container;
- conflito com instituicao existente;
- conflito com servicos internos;
- slug malicioso;
- URL publica incorreta;
- quebra de configuracao YAML;
- rota inesperada no proxy.

### Solucoes propostas

Validar e normalizar todos os campos antes de usar.

Regras recomendadas para slug publico:

```text
^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$
```

Regras recomendadas:

- gerar slug no servidor, nao confiar no cliente;
- impedir palavras reservadas;
- garantir unicidade;
- limitar tamanho;
- aceitar apenas caracteres seguros;
- separar `slug` publico de `tenant_id` interno;
- usar identificador interno imutavel;
- nunca montar comandos shell com input bruto;
- preferir APIs e bibliotecas em vez de shell.

## Problema 7: isolamento parcial entre instituicoes

### Risco

O projeto separa banco, usuario, volume e prefixo Redis por instituicao. Isso e positivo.

Mesmo assim, alguns riscos continuam:

- erro de configuracao pode apontar uma escola para banco de outra;
- prefixo Redis duplicado pode misturar sessoes/cache;
- backup ou restore incorreto pode sobrescrever dados;
- permissao excessiva no banco pode permitir acesso cruzado;
- falha em plugin Moodle pode afetar o container da instituicao;
- atualizacao de imagem pode quebrar todas as instituicoes ao mesmo tempo.

### Solucoes propostas

Manter e reforcar isolamento:

- banco exclusivo por instituicao;
- usuario exclusivo por instituicao;
- senha exclusiva por instituicao;
- volume exclusivo por instituicao;
- prefixo Redis exclusivo por instituicao;
- limites de CPU e memoria por container;
- validacao automatica de configuracao antes do deploy;
- testes de acesso cruzado no banco;
- backups separados por instituicao;
- restore testado periodicamente.

Tambem e recomendado manter um registro central:

```text
tenant_id
slug
container_name
database_name
database_user
moodledata_volume
redis_prefix
status
created_at
updated_at
```

## Problema 8: Redis compartilhado com prefixos

### Risco

Redis compartilhado com prefixos e uma solucao comum, mas depende de configuracao correta.

Problemas possiveis:

- prefixo repetido entre instituicoes;
- Redis sem senha em rede ampla;
- comando destrutivo afetando todas as instituicoes;
- flush acidental;
- consumo excessivo de memoria por uma instituicao afetando outras.

### Solucoes propostas

- validar unicidade de `MOODLE_REDIS_PREFIX`;
- usar prefixos imutaveis por instituicao;
- restringir acesso ao Redis por rede interna;
- configurar senha quando aplicavel;
- monitorar memoria e quantidade de chaves;
- evitar comandos globais como `FLUSHALL`;
- considerar Redis separado para tenants grandes.

## Problema 9: backup, restore e continuidade

### Risco

Separar banco e volume por instituicao facilita backup, mas exige processo claro.

Sem isso, problemas comuns sao:

- backup incompleto;
- banco e `moodledata` de momentos diferentes;
- restore nao testado;
- perda de dados por volume removido;
- dificuldade de restaurar apenas uma instituicao;
- indisponibilidade longa em falha do servidor unico.

### Solucoes propostas

Para cada instituicao, o backup deve incluir:

- dump do banco da instituicao;
- volume `moodledata` da instituicao;
- metadados do tenant;
- versao da imagem Moodle;
- configuracoes relevantes.

Boas praticas:

- agendar backups automaticos;
- armazenar fora do servidor principal;
- criptografar backups;
- testar restore periodicamente;
- documentar RPO e RTO;
- manter plano de restauracao por instituicao.

## Problema 10: observabilidade e auditoria

### Risco

Em producao, quando algo falhar, sera necessario responder rapidamente:

- qual etapa falhou?
- qual instituicao foi afetada?
- quem solicitou a criacao?
- quais arquivos foram alterados?
- qual container foi criado?
- qual versao da imagem esta rodando?
- o healthcheck passou?

Sem logs estruturados e auditoria, a operacao fica manual e arriscada.

### Solucoes propostas

Adicionar:

- logs por instituicao;
- logs estruturados no provisionador;
- tabela de eventos de provisionamento;
- metricas de CPU, memoria, disco, banco e Redis;
- alertas de container parado;
- alertas de falha no cron;
- healthchecks HTTP por instituicao;
- trilha de auditoria para acoes administrativas.

## Problema 11: atualizacoes da imagem Moodle

### Risco

Todas as instituicoes usam a mesma imagem Moodle. Isso simplifica manutencao, mas tambem significa que uma imagem ruim pode afetar todas as instituicoes.

### Solucoes propostas

- versionar imagens de forma explicita;
- testar atualizacao em ambiente de homologacao;
- atualizar tenants em ondas;
- manter rollback para versao anterior;
- registrar a versao usada por cada instituicao;
- executar backup antes de upgrades;
- validar compatibilidade de plugins.

Exemplo:

```text
w3soft/moodle:2026.06.1
w3soft/moodle:2026.06.2
w3soft/moodle:2026.07.1
```

## Arquitetura recomendada para MVP de producao em servidor unico

Para uma primeira producao controlada, sem migrar imediatamente para Kubernetes, a recomendacao e:

- manter 1 servidor Docker bem protegido;
- manter Compose, mas gerado por templates;
- usar secrets locais com permissao `600`;
- separar API publica do worker de provisionamento;
- usar fila para provisionamento;
- implementar locks;
- validar YAML antes de aplicar;
- validar Caddy antes de recarregar;
- executar healthcheck final;
- registrar auditoria;
- ter backup automatico por instituicao;
- monitorar recursos por container;
- restringir acesso ao Docker socket.

Fluxo sugerido:

```text
1. Usuario solicita criacao da instituicao
2. API valida dados
3. API cria registro Pending
4. API publica job na fila
5. Worker assume lock do tenant
6. Worker gera credenciais
7. Worker cria banco e usuario
8. Worker cria secret
9. Worker gera configuracao do servico
10. Worker valida Compose
11. Worker sobe container
12. Worker atualiza proxy
13. Worker executa healthcheck
14. Worker marca tenant como Active
```

## Arquitetura recomendada para producao mais robusta

Quando o numero de instituicoes crescer ou quando a criticidade aumentar, considerar migrar para:

- Kubernetes;
- Nomad;
- AWS ECS;
- outro orquestrador gerenciado.

Nesse modelo:

- secrets ficam em Secret Manager ou Kubernetes Secrets;
- cada instituicao vira um conjunto declarativo de recursos;
- ingress e rotas sao dinamicos;
- healthchecks e restarts sao nativos;
- limites de recurso sao controlados pelo orquestrador;
- rollbacks sao mais seguros;
- deploys podem ser automatizados por pipeline.

## Checklist minimo antes de producao

- `secrets/` com permissao `700`.
- `secrets/*.env` com permissao `600`.
- Nenhum secret real versionado no Git.
- Provisionador fora da internet publica.
- API com autenticacao e autorizacao fortes.
- Dados de entrada validados e normalizados.
- Slug unico e seguro.
- `tenant_id` interno imutavel.
- Banco e usuario exclusivos por instituicao.
- Senha forte e unica por instituicao.
- Prefixo Redis unico por instituicao.
- Compose validado antes de aplicar.
- Proxy validado antes de recarregar.
- Healthcheck obrigatorio antes de ativar tenant.
- Logs e auditoria do provisionamento.
- Backup automatico por instituicao.
- Restore testado.
- Monitoramento de containers, banco, Redis e disco.
- Plano de rollback para imagem Moodle.
- Processo de rotacao de secrets.

## Conclusao

A abordagem atual e adequada como laboratorio e como base para um MVP, mas nao deve ir para producao exatamente nesse formato.

O desenho de separar instituicoes por container, banco, usuario, volume e prefixo Redis e bom. O que precisa evoluir e a camada operacional: secrets, provisionamento, auditoria, validacao, rollback, backup, observabilidade e controle de acesso ao Docker.

O caminho mais seguro e transformar a criacao de instituicoes em um fluxo assíncrono, idempotente e auditavel, executado por um worker protegido, com estado persistido em banco e validacoes antes de cada mudanca na infraestrutura.
