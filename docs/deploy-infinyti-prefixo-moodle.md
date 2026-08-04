# Publicar o Moodle em `www.infinyti.net.br/moodle`

Esta configuracao usa o seguinte fluxo:

```text
Internet -> Nginx (HTTPS) -> Caddy (127.0.0.1:8088) -> container Moodle
```

As instituicoes ficam diretamente abaixo de `/moodle`, sem o segmento `/i`:

```text
https://www.infinyti.net.br/moodle/colegio-real
https://www.infinyti.net.br/moodle/colegio-modelo
```

## 1. Instalar o trecho do Nginx

O arquivo versionado esta em:

```text
deploy/nginx/moodle-proxy.conf
```

Inclua-o dentro do bloco `server` HTTPS que atende `www.infinyti.net.br`:

```nginx
include /home/projetos/moodle-docker/deploy/nginx/moodle-proxy.conf;
```

O bloco HTTP do dominio deve continuar redirecionando para HTTPS. Depois da
alteracao, valide e recarregue o Nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 2. Atualizar o Caddy local do servidor

`proxy/Caddyfile.local` nao e versionado. O arquivo completo de producao fica
versionado como modelo e pode ser copiado depois de cada alteracao intencional:

```bash
cp proxy/Caddyfile.production.example proxy/Caddyfile.local
```

O modelo preserva o prefixo `/moodle` ao encaminhar a requisicao. Nao use
`handle_path`, pois o entrypoint da imagem configura o Apache para receber o
caminho publico completo.

## 3. Atualizar `MOODLE_URL` de cada instituicao

Os arquivos `secrets/*.env` tambem nao sao versionados. Em cada arquivo de
tenant no servidor, configure a URL correspondente e habilite explicitamente o
proxy SSL:

```dotenv
MOODLE_URL=https://www.infinyti.net.br/moodle/SLUG_DA_INSTITUICAO
MOODLE_SSL_PROXY=true
```

Para as rotas existentes, os valores sao:

```dotenv
https://www.infinyti.net.br/moodle/escola-modelo
https://www.infinyti.net.br/moodle/escola-teste
https://www.infinyti.net.br/moodle/colegio-15-de-novembro
https://www.infinyti.net.br/moodle/colegio-monsenhor-adelmar-da-mota-valenca
https://www.infinyti.net.br/moodle/colegio-modelo
https://www.infinyti.net.br/moodle/colegio-presbiteriano-quinze-de-novembro
https://www.infinyti.net.br/moodle/colegio-real
https://www.infinyti.net.br/moodle/colegio-tiradentes-cpm
https://www.infinyti.net.br/moodle/colegio-batista-caruaru
```

`MOODLE_URL` nao deve terminar com `/`. O entrypoint extrai esse caminho e cria
o Alias correspondente no Apache quando o container e recriado.

## 4. Recriar os servicos

A alteracao em `moodle/config.php` exige uma nova imagem. As alteracoes nos
arquivos de ambiente exigem a recriacao de todos os containers de tenant.

Primeiro reconstrua a imagem compartilhada pelo servico `moodle` do Compose
base:

```bash
docker compose -f docker-compose.yml build moodle
```

Depois recrie a infraestrutura e todos os tenants usando os arquivos Compose do
servidor:

```bash

docker compose \
  -f docker-compose.infra.yml \
  -f docker-compose.instituicoes.yml \
  up -d --force-recreate
```

## 5. Validar

Primeiro valide o Caddy diretamente pelo loopback, enviando os cabecalhos que o
Nginx enviara:

```bash
curl -I \
  -H 'Host: www.infinyti.net.br' \
  -H 'X-Forwarded-Proto: https' \
  http://127.0.0.1:8088/moodle/colegio-real/
```

Depois valide o fluxo publico completo:

```bash
curl -I https://www.infinyti.net.br/moodle/
curl -I https://www.infinyti.net.br/moodle/colegio-real/
```

A porta 8088 fica vinculada somente a `127.0.0.1`, portanto nao deve responder
quando acessada externamente pelo IP do servidor.
