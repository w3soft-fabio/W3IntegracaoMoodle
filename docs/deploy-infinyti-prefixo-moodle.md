# Publicação no prefixo `/moodle`

O tráfego de produção segue este caminho:

```text
Internet -> Nginx HTTPS -> Caddy 127.0.0.1:8088 -> Moodle da instituição
```

Inclua `deploy/nginx/moodle-proxy.conf` no servidor HTTPS do domínio e valide o
Nginx antes do reload. O Caddy usa o arquivo versionado `proxy/Caddyfile`; não é
necessário copiar ou editar uma configuração local.

As rotas das instituições são criadas pelo worker em
`proxy/tenants/{slug}.caddy`. Cada snippet preserva o prefixo público completo e
encaminha `Host` interno, `X-Forwarded-Proto` e `X-Forwarded-Port` de acordo com
a URL recebida pela API.

Para validar o fluxo:

```bash
docker compose -f docker-compose.infra.yml config --quiet
docker exec moodle_proxy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
curl -I https://www.infinyti.net.br/moodle/
curl -I https://www.infinyti.net.br/moodle/SLUG/
```

A porta `8088` permanece vinculada apenas a `127.0.0.1`.
