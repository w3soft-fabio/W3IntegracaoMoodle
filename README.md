# Moodle Docker

Infraestrutura compartilhada e imagem Moodle usadas pelo Moodle Provisioner.
A criação de instituições acontece exclusivamente pela API e pelo worker .NET;
este repositório não possui um segundo fluxo manual de provisionamento.

## Estrutura principal

```text
docker-compose.infra.yml              MariaDB, Redis e Caddy compartilhados
moodle/                               imagem e bootstrap explícito do Moodle
generated/instituicoes/{slug}/        Compose e ambiente gerados pelo worker
proxy/Caddyfile                       configuração base versionada
proxy/tenants/{slug}.caddy            rota isolada gerada pelo worker
.provisioner/                         SQLite, chaves, locks e imagem atual
```

`generated/`, snippets, banco, chaves e arquivos `.env` são dados de runtime e
não devem ser versionados.

## Início rápido

1. Crie `secrets/infra.local.env` com `MARIADB_ROOT_PASSWORD`.
2. Prepare uma imagem imutável e suba a infraestrutura:

```bash
scripts/build-and-prepare-moodle.sh 2026.08.1 <commit-ou-refs/tags/...>
```

3. Inicie a API e o worker com os modelos em `systemd/` ou diretamente:

```bash
dotnet MoodleProvisioner.Api.dll
dotnet MoodleProvisioner.Api.dll --worker
```

4. Crie instituições por `POST /api/instituicoes` e acompanhe a URL retornada no
header `Location`.

Consulte [provisionamento de instituições](docs/provisionamento-instituicoes.md),
[cron centralizado](docs/cron-moodle-systemd.md) e
[deploy no prefixo `/moodle`](docs/deploy-infinyti-prefixo-moodle.md).
