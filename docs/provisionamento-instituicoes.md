# Provisionamento de instituições

## Fluxo único

```text
POST /api/instituicoes
  -> SQLite: instituição pendente + tarefa
  -> worker: preflight, artefatos, banco, volume e bootstrap
  -> worker: container, rota, healthcheck REST e ativação
  -> SQLite: instituição ativa + token protegido
```

A API responde `202 Accepted` e não acessa Docker. Somente o processo iniciado
com `--worker` recebe acesso à infraestrutura. Instituições ativas no SQLite são
a única fonte usada pelos demais endpoints Moodle.

## Artefatos

Cada instituição possui um diretório isolado:

```text
generated/instituicoes/{slug}/docker-compose.yml
generated/instituicoes/{slug}/moodle.env
proxy/tenants/{slug}.caddy
```

O `moodle.env` recebe permissão `0600`. O Caddy monta somente `proxy/tenants`,
portanto não enxerga senhas. O Compose usa a imagem registrada no momento da
solicitação e conecta o tenant à rede externa `moodle_net`.

## Operação

```bash
# infraestrutura compartilhada
docker compose -f docker-compose.infra.yml ps

# validar ou operar uma instituição
docker compose \
  -p moodle-SLUG \
  -f generated/instituicoes/SLUG/docker-compose.yml \
  config

docker compose \
  -p moodle-SLUG \
  -f generated/instituicoes/SLUG/docker-compose.yml \
  logs --tail=200
```

Consulte `GET /api/provisionamentos/{tarefaId}` para identificar a etapa com
falha. Depois de corrigir a infraestrutura, use
`POST /api/provisionamentos/{tarefaId}/reprocessar`; etapas concluídas não são
repetidas.

Não edite os artefatos para criar outra instituição. Alterações manuais podem
ser sobrescritas em um reprocessamento.
