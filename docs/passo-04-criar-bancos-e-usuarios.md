# Passo 4: Criar bancos e usuarios por instituicao

## Objetivo deste passo

Neste passo, o objetivo e criar um banco de dados logico e um usuario de banco exclusivo para cada instituicao Moodle.

Isso e uma parte central da arquitetura multi-instituicao recomendada:

```text
MariaDB compartilhado
  |
  +-- banco: moodle_escola_a
  |     usuario: moodle_escola_a
  |
  +-- banco: moodle_escola_b
  |     usuario: moodle_escola_b
  |
  +-- banco: moodle_escola_c
        usuario: moodle_escola_c
```

A ideia e simples:

- existe apenas um container MariaDB compartilhado;
- cada instituicao tem seu proprio banco;
- cada instituicao tem seu proprio usuario;
- o usuario de uma instituicao nao deve acessar o banco de outra.

Esse passo ainda nao sobe os containers Moodle por instituicao. Ele prepara o banco para que, no proximo passo, cada Moodle possa usar suas proprias credenciais.

## O que voce vai aprender neste passo

Ao implementar este passo localmente, voce vai praticar:

- iniciar apenas o container de banco;
- usar `docker compose -f` para escolher um arquivo Compose especifico;
- verificar containers em execucao;
- executar comandos dentro de um container com `docker compose exec`;
- acessar o MariaDB dentro do container;
- criar bancos de dados;
- criar usuarios de banco;
- conceder permissoes com `GRANT`;
- testar se um usuario consegue acessar somente o banco correto;
- entender a diferenca entre container, banco logico e usuario de banco.

## Resultado esperado

Ao final deste passo, voce tera:

```text
Container:
  moodle_db

Bancos:
  moodle_escola_a
  moodle_escola_b

Usuarios:
  moodle_escola_a
  moodle_escola_b
```

E as permissoes deverao ficar assim:

```text
Usuario moodle_escola_a -> acessa somente moodle_escola_a
Usuario moodle_escola_b -> acessa somente moodle_escola_b
```

## Conceitos rapidos antes dos comandos

### Container MariaDB

O container e o processo Docker que executa o servidor MariaDB.

Neste projeto, o container se chama:

```text
moodle_db
```

Ele e criado a partir do servico `db` definido no arquivo:

```text
docker-compose.infra.yml
```

### Banco logico

Dentro de um unico servidor MariaDB, voce pode ter varios bancos logicos.

Exemplo:

```text
moodle_escola_a
moodle_escola_b
moodle_escola_c
```

Eles estao dentro do mesmo container MariaDB, mas armazenam dados separados.

### Usuario de banco

O usuario de banco e a credencial que uma aplicacao usa para acessar um banco.

Exemplo:

```text
Usuario: moodle_escola_a
Senha:   senha-local-escola-a
Banco:   moodle_escola_a
```

O Moodle da escola A devera usar esse usuario. Ele nao deve usar o usuario `root`.

### Usuario `root`

O usuario `root` do MariaDB tem permissao administrativa.

Neste passo, vamos usar o `root` somente para criar bancos e usuarios.

Depois disso, cada Moodle devera usar seu proprio usuario restrito.

## Arquivos envolvidos

Arquivos usados neste passo:

```text
docker-compose.infra.yml
secrets/infra.local.env
```

Arquivo que sera criado neste passo:

```text
docs/passo-04-criar-bancos-e-usuarios.md
```

Arquivos que nao precisam ser alterados neste passo:

```text
docker-compose.yml
moodle/Dockerfile
moodle/config.php
moodle/php.ini
```

Opcionalmente, ao final, voce podera criar um arquivo SQL para repetir a criacao dos bancos:

```text
scripts/create-local-tenants.sql
```

Mas a primeira execucao sera manual para fins de aprendizado.

## Dados usados no ambiente local

Neste guia, vamos criar duas instituicoes de teste:

```text
escola_a
escola_b
```

Os bancos serao:

```text
moodle_escola_a
moodle_escola_b
```

Os usuarios serao:

```text
moodle_escola_a
moodle_escola_b
```

As senhas locais de exemplo serao:

```text
senha-local-escola-a
senha-local-escola-b
```

Importante: essas senhas sao apenas para laboratorio local. Em producao, use senhas fortes, unicas e armazenadas como secrets.

## Etapa 1: Entrar na pasta do projeto

Execute:

```sh
cd "/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker"
```

Confirme a pasta atual:

```sh
pwd
```

Resultado esperado:

```text
/Users/maxwellfarias/Documents/Projects/1. w3Soft/moodle-docker
```

Liste os arquivos:

```sh
ls
```

Resultado esperado, no minimo:

```text
docker-compose.infra.yml
docker-compose.yml
docs
moodle
proxy
secrets
```

## Etapa 2: Conferir a senha root local do MariaDB

O arquivo `docker-compose.infra.yml` usa o arquivo:

```text
secrets/infra.local.env
```

Confira o conteudo:

```sh
sed -n '1,40p' secrets/infra.local.env
```

Resultado esperado:

```text
MARIADB_ROOT_PASSWORD=rootpass-local
```

Neste guia, a senha administrativa local do MariaDB sera:

```text
rootpass-local
```

Se o seu arquivo tiver outro valor, use o valor do seu arquivo nos comandos abaixo.

## Etapa 3: Subir o container MariaDB compartilhado

Suba apenas o servico `db` da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml up -d db
```

O que esse comando faz:

- `docker compose`: usa o Docker Compose;
- `-f docker-compose.infra.yml`: escolhe o arquivo Compose da infraestrutura;
- `up`: cria e inicia os containers;
- `-d`: executa em segundo plano;
- `db`: sobe apenas o servico de banco.

Verifique se o container esta rodando:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Resultado esperado:

```text
NAMES       STATUS                    PORTS
moodle_db   Up ... seconds (healthy)
```

Se o status ainda estiver como `starting`, aguarde alguns segundos e rode o comando novamente.

## Etapa 4: Ver logs do banco

Verifique os logs do MariaDB:

```sh
docker compose -f docker-compose.infra.yml logs db
```

Procure mensagens indicando que o MariaDB iniciou corretamente.

Se quiser acompanhar os logs em tempo real:

```sh
docker compose -f docker-compose.infra.yml logs -f db
```

Para sair do modo em tempo real, pressione:

```text
Ctrl + C
```

## Etapa 5: Entrar no MariaDB como root

Agora vamos acessar o MariaDB dentro do container.

Execute:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -p
```

Quando pedir a senha, digite:

```text
rootpass-local
```

Observacao: ao digitar a senha, o terminal normalmente nao mostra caracteres. Isso e normal.

Se funcionar, voce vera um prompt parecido com:

```text
MariaDB [(none)]>
```

Isso significa que voce esta dentro do cliente MariaDB.

## Etapa 6: Ver bancos existentes

Dentro do prompt do MariaDB, execute:

```sql
SHOW DATABASES;
```

Resultado esperado: aparecerao bancos internos como:

```text
information_schema
mysql
performance_schema
sys
```

Se voce ja tiver usado este ambiente antes, tambem podem aparecer bancos Moodle antigos.

## Etapa 7: Criar o banco e usuario da escola A

Ainda dentro do prompt do MariaDB, execute:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

ALTER USER 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

GRANT ALL PRIVILEGES ON moodle_escola_a.*
  TO 'moodle_escola_a'@'%';

FLUSH PRIVILEGES;
```

O que cada comando faz:

- `CREATE DATABASE`: cria o banco da instituicao;
- `CHARACTER SET utf8mb4`: permite armazenar caracteres Unicode, incluindo emojis e acentos;
- `COLLATE utf8mb4_unicode_ci`: define a regra de comparacao de textos;
- `CREATE USER`: cria o usuario que o Moodle usara;
- `ALTER USER`: garante a senha correta mesmo se o usuario ja existir;
- `GRANT ALL PRIVILEGES ON moodle_escola_a.*`: concede acesso apenas ao banco `moodle_escola_a`;
- `FLUSH PRIVILEGES`: recarrega as permissoes.

## Etapa 8: Criar o banco e usuario da escola B

Ainda dentro do prompt do MariaDB, execute:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_b
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_b'@'%'
  IDENTIFIED BY 'senha-local-escola-b';

ALTER USER 'moodle_escola_b'@'%'
  IDENTIFIED BY 'senha-local-escola-b';

GRANT ALL PRIVILEGES ON moodle_escola_b.*
  TO 'moodle_escola_b'@'%';

FLUSH PRIVILEGES;
```

Agora existem dois bancos e dois usuarios separados.

## Etapa 9: Confirmar que os bancos foram criados

Dentro do prompt do MariaDB, execute:

```sql
SHOW DATABASES LIKE 'moodle_escola_%';
```

Resultado esperado:

```text
+------------------------------+
| Database (moodle_escola_%)    |
+------------------------------+
| moodle_escola_a               |
| moodle_escola_b               |
+------------------------------+
```

## Etapa 10: Confirmar que os usuarios foram criados

Execute:

```sql
SELECT User, Host
FROM mysql.user
WHERE User LIKE 'moodle_escola_%'
ORDER BY User, Host;
```

Resultado esperado:

```text
+------------------+------+
| User             | Host |
+------------------+------+
| moodle_escola_a  | %    |
| moodle_escola_b  | %    |
+------------------+------+
```

O host `%` significa que esse usuario pode conectar a partir de outros containers da rede Docker.

## Etapa 11: Ver permissoes da escola A

Execute:

```sql
SHOW GRANTS FOR 'moodle_escola_a'@'%';
```

Resultado esperado deve incluir algo como:

```text
GRANT ALL PRIVILEGES ON `moodle_escola_a`.* TO `moodle_escola_a`@`%`
```

O ponto importante e que o grant aponta para:

```text
moodle_escola_a.*
```

Ele nao deve apontar para:

```text
*.*
```

Se aparecer `*.*`, o usuario esta com permissao ampla demais para a arquitetura proposta.

## Etapa 12: Ver permissoes da escola B

Execute:

```sql
SHOW GRANTS FOR 'moodle_escola_b'@'%';
```

Resultado esperado deve incluir:

```text
GRANT ALL PRIVILEGES ON `moodle_escola_b`.* TO `moodle_escola_b`@`%`
```

Novamente, confirme que o usuario da escola B acessa apenas:

```text
moodle_escola_b.*
```

## Etapa 13: Sair do MariaDB

Para sair do prompt do MariaDB, execute:

```sql
exit;
```

Voce voltara para o terminal normal.

## Etapa 14: Testar login da escola A

Agora vamos testar se o usuario da escola A consegue acessar o banco da escola A.

Execute no terminal:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_a -psenha-local-escola-a moodle_escola_a -e "SELECT DATABASE();"
```

Resultado esperado:

```text
+------------------+
| DATABASE()       |
+------------------+
| moodle_escola_a  |
+------------------+
```

Detalhe importante: neste comando, a senha aparece logo depois de `-p`, sem espaco:

```text
-psenha-local-escola-a
```

Se voce escrever `-p senha-local-escola-a`, o cliente MariaDB pode interpretar a senha como outro argumento.

## Etapa 15: Testar login da escola B

Execute:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_b -psenha-local-escola-b moodle_escola_b -e "SELECT DATABASE();"
```

Resultado esperado:

```text
+------------------+
| DATABASE()       |
+------------------+
| moodle_escola_b  |
+------------------+
```

## Etapa 16: Testar isolamento de permissoes

Agora vamos confirmar que o usuario da escola A nao consegue acessar o banco da escola B.

Execute:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_a -psenha-local-escola-a moodle_escola_b -e "SELECT DATABASE();"
```

Resultado esperado: o comando deve falhar com uma mensagem parecida com:

```text
ERROR 1044 (42000): Access denied for user 'moodle_escola_a'@'%' to database 'moodle_escola_b'
```

Esse erro e bom neste teste. Ele confirma que o usuario da escola A nao acessa o banco da escola B.

Agora teste o contrario:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_b -psenha-local-escola-b moodle_escola_a -e "SELECT DATABASE();"
```

Resultado esperado:

```text
ERROR 1044 (42000): Access denied for user 'moodle_escola_b'@'%' to database 'moodle_escola_a'
```

## Etapa 17: Ver quais bancos cada usuario enxerga

Teste com o usuario da escola A:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_a -psenha-local-escola-a -e "SHOW DATABASES;"
```

Resultado esperado: ele deve enxergar algo parecido com:

```text
+--------------------+
| Database           |
+--------------------+
| information_schema |
| moodle_escola_a    |
+--------------------+
```

Teste com o usuario da escola B:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_b -psenha-local-escola-b -e "SHOW DATABASES;"
```

Resultado esperado:

```text
+--------------------+
| Database           |
+--------------------+
| information_schema |
| moodle_escola_b    |
+--------------------+
```

## Etapa 18: Criar arquivos `.env` futuros por instituicao

Este passo cria bancos e usuarios. No passo seguinte, cada container Moodle precisara saber quais credenciais usar.

Por enquanto, voce pode apenas planejar os arquivos:

```text
secrets/escola-a.local.env
secrets/escola-b.local.env
```

Conteudo futuro para a escola A:

```env
MOODLE_URL=http://localhost:8088/i/escola-a
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_a
MOODLE_DB_USER=moodle_escola_a
MOODLE_DB_PASSWORD=senha-local-escola-a
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola_a
MOODLE_TENANT_ID=escola-a-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_a_
```

Conteudo futuro para a escola B:

```env
MOODLE_URL=http://localhost:8088/i/escola-b
MOODLE_DB_HOST=db
MOODLE_DB_NAME=moodle_escola_b
MOODLE_DB_USER=moodle_escola_b
MOODLE_DB_PASSWORD=senha-local-escola-b
MOODLE_DATAROOT=/var/www/moodledata
MOODLE_PUBLIC_SLUG=escola_b
MOODLE_TENANT_ID=escola-b-local
MOODLE_REDIS_HOST=redis
MOODLE_REDIS_PORT=6379
MOODLE_REDIS_PREFIX=escola_b_
```

Esses arquivos serao usados quando os containers Moodle por instituicao forem criados.

## Etapa 19: Opcional - criar um script SQL versionavel

Depois de entender os comandos manualmente, voce pode criar um arquivo SQL para repetir esse processo em um ambiente local novo.

Crie a pasta:

```sh
mkdir -p scripts
```

Crie o arquivo:

```sh
touch scripts/create-local-tenants.sql
```

Abra no editor:

```sh
code scripts/create-local-tenants.sql
```

ou:

```sh
nano scripts/create-local-tenants.sql
```

Cole:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

ALTER USER 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';

GRANT ALL PRIVILEGES ON moodle_escola_a.*
  TO 'moodle_escola_a'@'%';

CREATE DATABASE IF NOT EXISTS moodle_escola_b
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'moodle_escola_b'@'%'
  IDENTIFIED BY 'senha-local-escola-b';

ALTER USER 'moodle_escola_b'@'%'
  IDENTIFIED BY 'senha-local-escola-b';

GRANT ALL PRIVILEGES ON moodle_escola_b.*
  TO 'moodle_escola_b'@'%';

FLUSH PRIVILEGES;
```

Salve o arquivo.

Para executar esse SQL no container:

```sh
docker compose -f docker-compose.infra.yml exec -T db mariadb -uroot -prootpass-local < scripts/create-local-tenants.sql
```

Explicacao:

- `exec -T`: executa um comando sem terminal interativo;
- `db`: servico onde o comando sera executado;
- `mariadb`: cliente do MariaDB;
- `-uroot`: usuario administrativo;
- `-prootpass-local`: senha local;
- `< scripts/create-local-tenants.sql`: envia o arquivo SQL para o comando.

Observacao: o redirecionamento com `<` e interpretado pelo seu terminal local. O arquivo precisa existir na sua maquina, nao dentro do container.

## Etapa 20: Opcional - executar tudo sem entrar no prompt MariaDB

Tambem e possivel criar um banco e usuario com um unico comando usando `-e`.

Exemplo para uma nova instituicao `escola_c`:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -prootpass-local -e "CREATE DATABASE IF NOT EXISTS moodle_escola_c CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS 'moodle_escola_c'@'%' IDENTIFIED BY 'senha-local-escola-c'; ALTER USER 'moodle_escola_c'@'%' IDENTIFIED BY 'senha-local-escola-c'; GRANT ALL PRIVILEGES ON moodle_escola_c.* TO 'moodle_escola_c'@'%'; FLUSH PRIVILEGES;"
```

Esse formato e util para automacao, mas para aprender e melhor executar manualmente no prompt MariaDB primeiro.

## Etapa 21: Checklist de validacao

Execute estes comandos para validar o passo inteiro.

Ver container:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Esperado:

```text
moodle_db   Up ... (healthy)
```

Ver bancos:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -prootpass-local -e "SHOW DATABASES LIKE 'moodle_escola_%';"
```

Esperado:

```text
moodle_escola_a
moodle_escola_b
```

Ver usuarios:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -uroot -prootpass-local -e "SELECT User, Host FROM mysql.user WHERE User LIKE 'moodle_escola_%' ORDER BY User, Host;"
```

Esperado:

```text
moodle_escola_a  %
moodle_escola_b  %
```

Testar acesso correto da escola A:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_a -psenha-local-escola-a moodle_escola_a -e "SELECT DATABASE();"
```

Esperado:

```text
moodle_escola_a
```

Testar acesso incorreto da escola A ao banco da escola B:

```sh
docker compose -f docker-compose.infra.yml exec db mariadb -umoodle_escola_a -psenha-local-escola-a moodle_escola_b -e "SELECT DATABASE();"
```

Esperado:

```text
Access denied
```

## Como parar sem apagar os dados

Para parar a infraestrutura:

```sh
docker compose -f docker-compose.infra.yml down
```

Esse comando remove o container, mas mantem o volume do banco.

Quando voce subir de novo:

```sh
docker compose -f docker-compose.infra.yml up -d db
```

os bancos `moodle_escola_a` e `moodle_escola_b` ainda deverao existir.

## Como apagar tudo e recomecar do zero

Use esta parte apenas se voce quiser limpar o laboratorio local.

Primeiro, veja os volumes:

```sh
docker volume ls | grep moodle
```

Para apagar os containers e volumes da infraestrutura:

```sh
docker compose -f docker-compose.infra.yml down -v
```

Atencao: `-v` apaga os volumes associados ao Compose. Isso remove os dados do banco local.

Depois disso, se subir novamente:

```sh
docker compose -f docker-compose.infra.yml up -d db
```

voce precisara recriar os bancos e usuarios.

## Problemas comuns

### Erro: Cannot connect to the Docker daemon

Significa que o Docker Engine nao esta rodando.

Solucao:

1. Abra o Docker Desktop.
2. Aguarde inicializar.
3. Rode novamente:

```sh
docker info
```

### Erro: Access denied for user 'root'

Possiveis causas:

- a senha em `secrets/infra.local.env` nao e `rootpass-local`;
- o volume do banco ja existia com outra senha root;
- voce subiu outro Compose com outro valor de senha.

Confira o secret:

```sh
sed -n '1,40p' secrets/infra.local.env
```

Confira os volumes:

```sh
docker volume ls | grep moodle
```

Se for um laboratorio descartavel, voce pode limpar com:

```sh
docker compose -f docker-compose.infra.yml down -v
```

Depois suba de novo:

```sh
docker compose -f docker-compose.infra.yml up -d db
```

### Erro: user already exists

Se voce criou o usuario antes, pode aparecer erro ao tentar criar novamente sem `IF NOT EXISTS`.

Use:

```sql
CREATE USER IF NOT EXISTS 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';
```

Ou altere a senha:

```sql
ALTER USER 'moodle_escola_a'@'%'
  IDENTIFIED BY 'senha-local-escola-a';
```

### Erro: database exists

Se o banco ja existe, use:

```sql
CREATE DATABASE IF NOT EXISTS moodle_escola_a
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

### O comando com senha nao funciona

No cliente MariaDB, quando voce passa a senha na linha de comando, nao coloque espaco entre `-p` e a senha.

Correto:

```sh
-psenha-local-escola-a
```

Incorreto:

```sh
-p senha-local-escola-a
```

## Regras para producao

Em producao, mantenha as mesmas ideias, mas com mais cuidado:

- nao use senhas de exemplo;
- nao versionar arquivos reais de secrets;
- usar senhas fortes e unicas por instituicao;
- criar um usuario por banco;
- nunca usar `root` no `config.php` do Moodle;
- fazer backup antes de alterar permissoes;
- registrar quais bancos pertencem a quais instituicoes;
- testar restore de cada instituicao;
- considerar banco dedicado para clientes grandes.

## Resumo do passo 4

Neste passo voce preparou o MariaDB compartilhado para receber varias instalacoes Moodle.

Voce criou:

```text
moodle_escola_a
moodle_escola_b
```

E criou usuarios restritos:

```text
moodle_escola_a -> moodle_escola_a
moodle_escola_b -> moodle_escola_b
```

O ponto principal e que a infraestrutura pesada continua compartilhada, mas os dados de cada instituicao ficam separados por banco e usuario.

No proximo passo, cada container Moodle devera usar seu proprio arquivo `.env`, apontando para o banco e usuario correspondentes.

