# Subir o projeto Moodle em outro ambiente Windows

Este guia descreve o passo a passo para subir esta aplicacao em um computador
Windows com Docker Desktop instalado.

O foco deste roteiro e uma instalacao nova em outro ambiente, usando os arquivos
do projeto copiados para a maquina Windows. Se a intencao for migrar uma
instalacao ja existente com dados reais, leia tambem a secao "Instalacao nova
versus migracao com dados".

## 1. Entender o que precisa ser copiado

Copiar a pasta raiz do projeto e suficiente para levar:

- arquivos `docker-compose`;
- imagem Moodle customizada, via `moodle/Dockerfile`;
- configuracoes do Moodle;
- configuracao do Caddy;
- scripts;
- arquivos `secrets/*.env`;
- documentacao.

Porem a pasta raiz nao leva automaticamente:

- bancos MariaDB gravados em volumes Docker;
- arquivos enviados ao Moodle, cache e dados em `moodledata_*`;
- dados persistidos de Redis;
- certificados e dados internos do Caddy.

Esses dados ficam em volumes Docker, como:

```text
moodle_db_data
moodle_redis_data
moodledata_escola_a
moodledata_escola_b
moodle_caddy_data
moodle_caddy_config
```

Se o objetivo e apenas subir um ambiente novo, nao copie esses volumes. O Moodle
sera instalado do zero.

Se o objetivo e migrar um ambiente ja em uso, copie tambem os dumps do banco e
os dados dos volumes `moodledata_*`. Nao basta compactar a pasta do projeto.

## 2. Migrar um ambiente ja em uso

Em uma migracao real, o pacote precisa conter dados persistidos e nao apenas os
arquivos do projeto.

Leve, no minimo:

- pasta do projeto, incluindo `docker-compose*.yml`, `moodle`, `proxy`,
  `scripts`, `config` e `docs`;
- arquivos `secrets/*.env` usados no ambiente que sera migrado;
- dump MariaDB de cada banco Moodle, por exemplo `moodle_escola_a`;
- arquivo compactado de cada volume `moodledata_*`;
- lista de versoes usadas, principalmente tag da imagem Moodle e versao do
  MariaDB;
- se houver HTTPS publico no Caddy, avaliar tambem os volumes
  `moodle_caddy_data` e `moodle_caddy_config`, pois podem conter certificados.

Normalmente nao e necessario migrar `moodle_redis_data`, porque Redis tende a
guardar cache, locks e sessoes temporarias. Se o ambiente usa sessoes no Redis e
nao pode derrubar usuarios logados, planeje uma janela de manutencao.

### 2.1. Preparar uma janela de manutencao

Para evitar diferenca entre banco e arquivos, faca a copia com o Moodle sem
receber novas escritas.

Opcoes:

- colocar o Moodle em modo manutencao antes da copia;
- parar os containers Moodle das instituicoes durante a exportacao;
- fazer a copia em uma janela curta, avisando os usuarios.

Exemplo para parar uma instituicao:

```powershell
docker compose -f docker-compose.instituicoes.yml stop moodle_escola_a
```

Exemplo para parar todas:

```powershell
docker compose -f docker-compose.instituicoes.yml stop
```

Mantenha o MariaDB ligado enquanto gera os dumps.

### 2.2. Criar uma pasta de backup

No ambiente de origem, dentro da pasta do projeto:

```powershell
mkdir backup-migracao
```

No Linux ou macOS:

```bash
mkdir -p backup-migracao
```

### 2.3. Exportar os bancos MariaDB

Descubra os bancos existentes:

```powershell
docker exec moodle_db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW DATABASES;"'
```

Gere um dump por banco de instituicao. Exemplo para `moodle_escola_a`:

```powershell
docker exec moodle_db sh -c 'mariadb-dump --single-transaction --quick --routines --triggers --events -uroot -p"$MARIADB_ROOT_PASSWORD" moodle_escola_a' > backup-migracao\moodle_escola_a.sql
```

Repita para cada banco real:

```powershell
docker exec moodle_db sh -c 'mariadb-dump --single-transaction --quick --routines --triggers --events -uroot -p"$MARIADB_ROOT_PASSWORD" moodle_escola_b' > backup-migracao\moodle_escola_b.sql
```

Observacoes:

- prefira dump logico (`mariadb-dump`) em vez de copiar o volume
  `moodle_db_data` diretamente;
- o dump logico e mais portavel entre Windows, Linux, Docker Desktop e
  servidores;
- guarde cada dump com nome claro, associando banco e instituicao.

### 2.4. Exportar os volumes `moodledata_*`

Liste os volumes:

```powershell
docker volume ls
```

Exporte cada volume `moodledata_*` para um `.tgz`.

PowerShell no Windows:

```powershell
docker run --rm -v moodledata_escola_a:/data:ro -v "${PWD}\backup-migracao:/backup" alpine sh -c "cd /data && tar czf /backup/moodledata_escola_a.tgz ."
```

Linux ou macOS:

```bash
docker run --rm -v moodledata_escola_a:/data:ro -v "$(pwd)/backup-migracao:/backup" alpine sh -c "cd /data && tar czf /backup/moodledata_escola_a.tgz ."
```

Repita para cada instituicao:

```powershell
docker run --rm -v moodledata_escola_b:/data:ro -v "${PWD}\backup-migracao:/backup" alpine sh -c "cd /data && tar czf /backup/moodledata_escola_b.tgz ."
```

O `moodledata` guarda arquivos enviados, cache local, arquivos temporarios,
arquivos privados, repositorios locais e tambem dados criados pelo bootstrap,
como `w3soft/ws-token.txt`. Por isso ele precisa acompanhar o dump do banco.

### 2.5. Conferir o pacote antes de transferir

Confira os arquivos gerados:

```powershell
dir backup-migracao
```

Um pacote completo costuma ter este formato:

```text
backup-migracao\
  moodle_escola_a.sql
  moodle_escola_b.sql
  moodledata_escola_a.tgz
  moodledata_escola_b.tgz
```

Gere hashes para validar a copia no destino:

```powershell
Get-FileHash backup-migracao\*
```

No Linux ou macOS:

```bash
shasum -a 256 backup-migracao/*
```

### 2.6. Formas de compartilhar o pacote

Escolha a forma conforme tamanho, seguranca e velocidade.

Opcoes comuns:

- HD externo ou pendrive, bom para volumes grandes e rede lenta;
- pasta compartilhada de rede, como SMB no Windows;
- `scp` ou `rsync` para outro servidor;
- OneDrive, Google Drive, Dropbox ou similar, preferencialmente com arquivo
  compactado e protegido;
- S3, Azure Blob, Backblaze B2 ou outro storage privado;
- Git privado somente para codigo e documentacao, nunca para dumps, volumes ou
  secrets;
- registry Docker privado para publicar a imagem `w3soft/moodle`, quando nao
  quiser reconstruir a imagem no destino.

Recomendacoes:

- nao envie dumps de banco e `moodledata` sem criptografia quando houver dados
  reais de alunos, usuarios ou documentos;
- envie `secrets/*.env` por canal seguro separado, ou use um gerenciador de
  senhas;
- mantenha os hashes para conferir se a transferencia chegou intacta;
- registre de qual data e horario o backup foi tirado.

### 2.7. Restaurar os dados no Windows de destino

Copie a pasta do projeto para o Windows e coloque `backup-migracao` dentro dela:

```text
C:\Projetos\moodle-docker\backup-migracao
```

Suba apenas a infraestrutura:

```powershell
docker compose -f docker-compose.infra.yml up -d
```

Crie os bancos e usuarios conforme a secao "Criar bancos e usuarios das
instituicoes". Os nomes e senhas precisam bater com `secrets\*.local.env`.

Importe o dump de cada banco usando um container MariaDB temporario na mesma
rede Docker. Essa forma evita carregar arquivos grandes na memoria do
PowerShell.

```powershell
docker run --rm --network moodle_net --env-file .\secrets\infra.local.env -v "${PWD}\backup-migracao:/backup:ro" mariadb:10.11 sh -c 'mariadb -h db -uroot -p"$MARIADB_ROOT_PASSWORD" moodle_escola_a < /backup/moodle_escola_a.sql'
```

Repita para os outros bancos:

```powershell
docker run --rm --network moodle_net --env-file .\secrets\infra.local.env -v "${PWD}\backup-migracao:/backup:ro" mariadb:10.11 sh -c 'mariadb -h db -uroot -p"$MARIADB_ROOT_PASSWORD" moodle_escola_b < /backup/moodle_escola_b.sql'
```

Crie ou restaure cada volume `moodledata_*`:

```powershell
docker volume create moodledata_escola_a
docker run --rm -v moodledata_escola_a:/data -v "${PWD}\backup-migracao:/backup:ro" alpine sh -c "cd /data && tar xzf /backup/moodledata_escola_a.tgz"
```

Repita para cada instituicao:

```powershell
docker volume create moodledata_escola_b
docker run --rm -v moodledata_escola_b:/data -v "${PWD}\backup-migracao:/backup:ro" alpine sh -c "cd /data && tar xzf /backup/moodledata_escola_b.tgz"
```

Depois revise `MOODLE_URL` em cada arquivo `secrets\*.local.env`. A URL precisa
ser a URL real usada no navegador no novo ambiente.

Por fim, suba as instituicoes:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d
```

### 2.8. Validar a migracao

Depois de subir:

```powershell
docker compose -f docker-compose.infra.yml ps
docker compose -f docker-compose.instituicoes.yml ps
docker logs --tail=200 moodle_escola_a
```

No navegador, valide:

- login admin;
- usuarios e cursos existentes;
- arquivos enviados nos cursos;
- imagens e documentos;
- tarefas cron;
- token de integracao, se a API Moodle for usada;
- URL correta, sem redirecionar para o ambiente antigo.

## 3. Preparar o Windows

Instale e abra o Docker Desktop.

Confirme que o Docker esta rodando. No PowerShell, execute:

```powershell
docker version
docker compose version
docker ps
```

Se algum comando falhar, abra o Docker Desktop e aguarde ele iniciar
completamente.

Recomendacao para Windows:

- use PowerShell;
- mantenha o projeto em uma pasta simples, por exemplo `C:\Projetos\moodle-docker`;
- evite caminhos com acentos ou caracteres especiais;
- se possivel, use WSL 2 como backend do Docker Desktop.

## 4. Copiar e entrar na pasta do projeto

Descompacte ou copie o projeto para uma pasta local, por exemplo:

```text
C:\Projetos\moodle-docker
```

Entre na pasta pelo PowerShell:

```powershell
cd C:\Projetos\moodle-docker
```

Confira se os arquivos principais existem:

```powershell
dir
```

Voce deve ver, no minimo:

```text
docker-compose.yml
docker-compose.infra.yml
docker-compose.instituicoes.yml
moodle
proxy
secrets
scripts
config
docs
```

## 5. Escolher o modo de subida

O projeto tem dois modos:

- `docker-compose.yml`: modo simples/local, com um Moodle e um banco.
- `docker-compose.infra.yml` + `docker-compose.instituicoes.yml`: modo
  multi-instituicao, com infraestrutura compartilhada e um Moodle por escola.

Para reproduzir o ambiente multi-instituicao, use:

```text
docker-compose.infra.yml
docker-compose.instituicoes.yml
```

Os passos abaixo usam esse modo.

## 6. Revisar os arquivos de ambiente

Antes de subir os containers, revise os arquivos dentro de:

```text
secrets\
```

Arquivo da infraestrutura:

```text
secrets\infra.local.env
```

Arquivos das instituicoes:

```text
secrets\escola-a.local.env
secrets\escola-b.local.env
...
```

Em cada arquivo de escola, confira principalmente:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-local-escola-a
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=senha-do-admin
MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL=1
```

Para testar no proprio computador Windows, `localhost` esta correto:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
```

Para acessar a partir de outro computador da rede, troque `localhost` pelo IP da
maquina Windows:

```env
MOODLE_URL=http://IP_DA_MAQUINA_WINDOWS:8088/i/escola-a
```

Exemplo:

```env
MOODLE_URL=http://192.168.0.50:8088/i/escola-a
```

Importante: o valor de `MOODLE_URL` precisa ser exatamente a URL usada no
navegador, incluindo porta e caminho `/i/escola-a`.

## 7. Evitar o erro de admin pendente

Em algumas instalacoes novas, o Moodle pode ficar com o admin em estado pendente
apos a instalacao CLI. Isso pode gerar o erro:

```text
a instalacao deve ser concluida a partir do endereco IP original
```

Ou aparecer indiretamente como erro `502` ao acessar pelo Caddy.

Para reduzir esse risco, adicione temporariamente esta linha no arquivo da
instituicao que sera instalada:

```env
MOODLE_ADMIN_RESET_PASSWORD=1
```

Exemplo em:

```text
secrets\escola-a.local.env
```

Depois que o ambiente estiver instalado e o login admin funcionar, remova ou
troque para:

```env
MOODLE_ADMIN_RESET_PASSWORD=0
```

Isso evita que a senha do admin seja redefinida em todo restart.

## 8. Validar os arquivos Compose

No PowerShell, dentro da pasta do projeto, execute:

```powershell
docker compose -f docker-compose.infra.yml config
```

Depois:

```powershell
docker compose -f docker-compose.instituicoes.yml config
```

Se algum comando mostrar erro, corrija o arquivo indicado antes de continuar.

## 9. Construir a imagem Moodle

A stack das instituicoes usa a imagem:

```text
w3soft/moodle:2026.07.1-local
```

Construa essa imagem na maquina Windows:

```powershell
docker compose -f docker-compose.yml build moodle
```

Esse passo pode demorar porque a imagem baixa dependencias, clona o Moodle e
instala extensoes PHP.

Confirme se a imagem foi criada:

```powershell
docker images w3soft/moodle
```

## 10. Subir a infraestrutura compartilhada

Suba MariaDB, Redis e Caddy:

```powershell
docker compose -f docker-compose.infra.yml up -d
```

Confira os containers:

```powershell
docker compose -f docker-compose.infra.yml ps
```

Resultado esperado:

```text
moodle_db
moodle_redis
moodle_proxy
```

Tambem confira pelo Docker:

```powershell
docker ps
```

Teste o Redis:

```powershell
docker exec moodle_redis redis-cli ping
```

Resultado esperado:

```text
PONG
```

Teste o MariaDB:

```powershell
docker exec moodle_db mariadb --version
```

## 11. Criar bancos e usuarios das instituicoes

Antes de subir os Moodles das escolas, crie os bancos e usuarios no MariaDB.

Entre no MariaDB como root:

```powershell
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -p
```

Digite a senha definida em:

```text
secrets\infra.local.env
```

Procure a variavel:

```env
MARIADB_ROOT_PASSWORD=...
```

Dentro do prompt do MariaDB, crie o banco e o usuario da escola.

Exemplo para `escola-a`:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

GRANT ALL PRIVILEGES ON moodle_escola_a.*
  TO 'moodle_escola_a'@'%';

FLUSH PRIVILEGES;
```

Os valores precisam bater com o arquivo:

```text
secrets\escola-a.local.env
```

Mapeamento:

```text
MOODLE_DB_NAME     -> nome do banco
MOODLE_DB_USER     -> usuario do banco
MOODLE_DB_PASSWORD -> senha do usuario
```

Repita para cada escola que sera subida.

Para sair do MariaDB:

```sql
exit;
```

## 12. Subir as instituicoes

Para subir todas as instituicoes configuradas em
`docker-compose.instituicoes.yml`:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d
```

Para subir apenas uma instituicao, por exemplo `escola-a`:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d moodle_escola_a
```

Confira os containers:

```powershell
docker compose -f docker-compose.instituicoes.yml ps
```

Ou:

```powershell
docker ps --filter "name=moodle_escola"
```

## 13. Acompanhar a primeira instalacao

Na primeira subida, cada container Moodle instala o banco, roda upgrade e executa
o provisionamento.

Acompanhe os logs da escola:

```powershell
docker logs -f moodle_escola_a
```

Mensagens esperadas:

```text
Moodle database is empty. Running non-interactive installation.
Moodle database installation finished.
Running Moodle CLI upgrade check.
Running tenant provisioning.
Automatic Moodle bootstrap finished.
```

Para sair do log em tempo real, pressione:

```text
Ctrl + C
```

## 14. Acessar pelo navegador

Com as portas padrao atuais, acesse:

```text
http://localhost:8088
http://localhost:8088/i/escola-a/
http://localhost:8088/i/escola-b/
```

Se estiver acessando de outro computador da rede, use o IP da maquina Windows:

```text
http://IP_DA_MAQUINA_WINDOWS:8088/i/escola-a/
```

Exemplo:

```text
http://192.168.0.50:8088/i/escola-a/
```

## 15. Validar login admin

Use os dados do arquivo da escola:

```text
secrets\escola-a.local.env
```

Campos:

```env
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=...
```

Se `MOODLE_ADMIN_FORCE_PASSWORD_CHANGE_ON_INSTALL=1`, o Moodle pode pedir troca
de senha no primeiro login.

Depois de confirmar que o login funciona, remova ou desative:

```env
MOODLE_ADMIN_RESET_PASSWORD=1
```

Depois recrie o container para aplicar a mudanca:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

## 16. Diagnostico de erro 502

Erro `502` no navegador significa que o Caddy recebeu a requisicao, mas nao
conseguiu obter uma resposta valida do container Moodle.

Confira se o container da escola esta rodando:

```powershell
docker ps --filter "name=moodle_escola_a"
```

Veja os logs do Moodle:

```powershell
docker logs --tail=200 moodle_escola_a
```

Veja os logs do proxy:

```powershell
docker logs --tail=200 moodle_proxy
```

Confira se a escola existe no Caddyfile:

```text
proxy\Caddyfile.local
```

Deve haver uma rota parecida com:

```caddy
@a path /i/escola-a/*

handle @a {
    reverse_proxy moodle_escola_a:80
}
```

Confira se o container esta na mesma rede:

```powershell
docker inspect moodle_escola_a
docker inspect moodle_proxy
```

Ambos devem estar na rede:

```text
moodle_net
```

## 17. Diagnostico de admin pendente ou installhijacked

Se os logs ou a tela indicarem algo como:

```text
a instalacao deve ser concluida a partir do endereco IP original
```

Ou se o banco mostrar:

```text
admin.password = adminsetuppending
admin.lastip = 0.0.0.0
```

Ative temporariamente:

```env
MOODLE_ADMIN_RESET_PASSWORD=1
```

No arquivo da escola:

```text
secrets\escola-a.local.env
```

Recrie o container:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

Confira os logs:

```powershell
docker logs --tail=200 moodle_escola_a
```

Depois teste o login novamente.

Quando funcionar, desative a redefinicao permanente:

```env
MOODLE_ADMIN_RESET_PASSWORD=0
```

E recrie mais uma vez:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

## 18. Diagnostico de MOODLE_URL incorreto

Se o Moodle redirecionar para `localhost` quando voce esta acessando de outra
maquina, o problema esta no `MOODLE_URL`.

Errado para acesso em rede:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
```

Certo para acesso em rede:

```env
MOODLE_URL=http://192.168.0.50:8088/i/escola-a
```

Depois de alterar, recrie o container:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

## 19. Ajuste recomendado para proxy reverso

Este projeto usa Caddy como proxy reverso. O Moodle precisa reconhecer que esta
atras de proxy para tratar corretamente IP, HTTPS e cabecalhos encaminhados.

No arquivo:

```text
moodle\config.php
```

Recomenda-se configurar o Moodle para proxy reverso. Um ajuste tipico e:

```php
$CFG->reverseproxy = true;
```

Observacao:

- adicione `$CFG->sslproxy = true;` somente quando o acesso publico for HTTPS
  no proxy;
- para ambiente somente HTTP local, `sslproxy` normalmente nao e necessario;
- o Caddy encaminha cabecalhos como `X-Forwarded-For` por padrao;
- se o Moodle continuar registrando o IP interno do container do Caddy, revise a
  configuracao `getremoteaddrconf` pelo Moodle ou pelo banco, conforme a versao
  instalada. Nao aplique um valor numerico sem confirmar o significado na versao
  atual do Moodle.

Exemplo para ambiente HTTPS publico:

```php
$CFG->reverseproxy = true;
$CFG->sslproxy = true;
```

Exemplo para ambiente HTTP local:

```php
$CFG->reverseproxy = true;
```

Depois de alterar `moodle\config.php`, reconstrua a imagem.

Reconstrua:

```powershell
docker compose -f docker-compose.yml build moodle
```

Recrie a escola:

```powershell
docker compose -f docker-compose.instituicoes.yml up -d --force-recreate moodle_escola_a
```

## 20. Parar o ambiente

Para parar as instituicoes:

```powershell
docker compose -f docker-compose.instituicoes.yml down
```

Para parar infraestrutura:

```powershell
docker compose -f docker-compose.infra.yml down
```

Esse comando para containers, mas mantem volumes.

## 21. Reiniciar do zero em ambiente de teste

Atencao: os comandos abaixo apagam os volumes Docker do projeto. Use somente em
ambiente de teste.

Pare as instituicoes:

```powershell
docker compose -f docker-compose.instituicoes.yml down -v
```

Pare a infraestrutura e remova volumes:

```powershell
docker compose -f docker-compose.infra.yml down -v
```

Depois suba novamente a partir do passo 8.

## 22. Instalacao nova versus migracao com dados

Use instalacao nova quando:

- voce quer apenas validar a aplicacao em outro computador;
- nao precisa manter cursos, usuarios, arquivos e historico;
- pode criar bancos vazios e deixar o bootstrap instalar o Moodle.

Use migracao com dados quando:

- ja existem usuarios, cursos ou arquivos reais;
- voce precisa manter o mesmo estado do Moodle;
- o banco e os arquivos enviados precisam ser preservados.

Para migracao com dados, o fluxo correto e:

1. exportar o banco MariaDB da origem;
2. copiar o conteudo dos volumes `moodledata_*`;
3. importar o banco no destino;
4. restaurar os dados nos volumes correspondentes;
5. revisar `MOODLE_URL`;
6. subir os containers.

Sem esses dados persistidos, a maquina Windows criara uma instalacao nova.

## 23. Checklist rapido

Antes de acessar no navegador, confirme:

- Docker Desktop esta rodando;
- `docker compose -f docker-compose.infra.yml config` nao mostra erro;
- `docker compose -f docker-compose.instituicoes.yml config` nao mostra erro;
- imagem `w3soft/moodle:2026.07.1-local` foi construida;
- `moodle_db`, `moodle_redis` e `moodle_proxy` estao rodando;
- bancos e usuarios das escolas foram criados;
- `MOODLE_URL` bate com a URL real usada no navegador;
- containers `moodle_escola_*` estao rodando;
- logs mostram `Automatic Moodle bootstrap finished`;
- `MOODLE_ADMIN_RESET_PASSWORD=1` foi usado apenas para destravar instalacao,
  e depois desativado.
