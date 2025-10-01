---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Instalação do auto-hospedeiro {#self-host-installation}

Oferecemos uma versão auto-hospedada do servidor Tuist para organizações que
necessitam de mais controlo sobre a sua infraestrutura. Esta versão permite-lhe
alojar o Tuist na sua própria infraestrutura, assegurando que os seus dados
permanecem seguros e privados.

> [IMPORTANTE] LICENÇA NECESSÁRIA A auto-hospedagem do Tuist requer uma licença
> paga legalmente válida. A versão local do Tuist está disponível apenas para
> organizações no plano Enterprise. Se estiver interessado nesta versão, entre
> em contacto com [contact@tuist.dev](mailto:contact@tuist.dev).

## Cadência de libertação {#release-cadence}

Nós lançamos novas versões do Tuist continuamente à medida que novas mudanças
liberáveis chegam ao main. Nós seguimos [versionamento
semântico](https://semver.org/) para assegurar um versionamento previsível e
compatibilidade.

O componente principal é utilizado para assinalar alterações de rutura no
servidor Tuist que exigirão coordenação com os utilizadores locais. Não deve
esperar que o utilizemos e, caso seja necessário, pode ter a certeza de que
trabalharemos consigo para que a transição seja suave.

## Implementação contínua {#continuous-deployment}

É altamente recomendável configurar um pipeline de implantação contínua que
implante automaticamente a versão mais recente do Tuist todos os dias. Isso
garante que você sempre tenha acesso aos recursos, melhorias e atualizações de
segurança mais recentes.

Aqui está um exemplo de fluxo de trabalho do GitHub Actions que verifica e
implanta novas versões diariamente:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## Requisitos de tempo de execução {#runtime-requirements}

Esta secção descreve os requisitos para alojar o servidor Tuist na sua
infraestrutura.

### Executar imagens virtualizadas do Docker {#running-dockervirtualized-images}

Distribuímos o servidor como uma imagem [Docker](https://www.docker.com/)
através do [Registo de Contentores do
GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Para o executar, a sua infraestrutura tem de suportar a execução de imagens
Docker. Note-se que a maioria dos fornecedores de infra-estruturas suportam-no
porque se tornou o contentor padrão para distribuir e executar software em
ambientes de produção.

### Base de dados Postgres {#postgres-database}

Para além de executar as imagens Docker, necessitará de uma [base de dados
Postgres](https://www.postgresql.org/) para armazenar dados relacionais. A
maioria dos fornecedores de infra-estruturas inclui bases de dados Postgres na
sua oferta (por exemplo, [AWS](https://aws.amazon.com/rds/postgresql/) e [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

Para uma análise de desempenho, utilizamos uma [extensão Timescale
Postgres](https://www.timescale.com/). É necessário certificar-se de que o
TimescaleDB está instalado na máquina que executa o banco de dados Postgres.
Siga as instruções de instalação
[aqui](https://docs.timescale.com/self-hosted/latest/install/) para saber mais.
Se não for possível instalar a extensão Timescale, é possível configurar seu
próprio painel de controle usando as métricas do Prometheus.

> [INFO] MIGRAÇÕES O ponto de entrada da imagem Docker executa automaticamente
> quaisquer migrações de esquema pendentes antes de iniciar o serviço.

### Base de dados ClickHouse {#clickhouse-database}

Para armazenar uma grande quantidade de dados, estamos a utilizar o
[ClickHouse](https://clickhouse.com/). Alguns recursos, como insights de
construção, só funcionarão com o ClickHouse ativado. O ClickHouse acabará por
substituir a extensão Timescale Postgres. É possível escolher entre
auto-hospedar o ClickHouse ou usar o serviço hospedado deles.

> [!INFO] MIGRAÇÕES O ponto de entrada da imagem Docker executa automaticamente
> quaisquer migrações de esquema ClickHouse pendentes antes de iniciar o
> serviço.

### Armazenamento {#armazenamento}

Você também precisará de uma solução para armazenar arquivos (por exemplo,
binários de estrutura e biblioteca). Atualmente, suportamos qualquer
armazenamento que seja compatível com S3.

## Configuração {#configuração}

A configuração do serviço é efectuada em tempo de execução através de variáveis
de ambiente. Dada a natureza sensível destas variáveis, aconselhamos a
encriptação e o armazenamento das mesmas em soluções de gestão de palavras-passe
seguras. Pode ter a certeza de que o Tuist trata estas variáveis com o máximo
cuidado, garantindo que nunca são apresentadas nos registos.

> [VERIFICAÇÕES DE LANÇAMENTO As variáveis necessárias são verificadas no
> arranque. Se alguma estiver em falta, o lançamento falhará e a mensagem de
> erro indicará as variáveis em falta.

### Configuração da licença {#license-configuration}

Como utilizador no local, receberá uma chave de licença que terá de expor como
uma variável de ambiente. Esta chave é utilizada para validar a licença e
garantir que o serviço está a ser executado de acordo com os termos do contrato.

| Variável de ambiente               | Descrição                                                                                                                                                                                                                                                                | Necessário | Predefinição | Exemplos                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ------------ | ----------------------------------------- |
| `TUIST_LICENSE`                    | A licença fornecida após a assinatura do acordo de nível de serviço                                                                                                                                                                                                      | Sim*       |              | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **Alternativa excecional ao `TUIST_LICENSE`**. Certificado público codificado em base64 para validação de licenças offline em ambientes com air-gap onde o servidor não pode contactar serviços externos. Utilizar apenas quando `TUIST_LICENSE` não puder ser utilizado | Sim*       |              | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* É necessário fornecer `TUIST_LICENSE` ou `TUIST_LICENSE_CERTIFICATE_BASE64`,
mas não ambos. Utilize `TUIST_LICENSE` para implementações padrão.

> [IMPORTANTE] DATA DE EXPIRAÇÃO As licenças têm uma data de expiração. Os
> utilizadores receberão um aviso ao utilizarem os comandos Tuist que interagem
> com o servidor se a licença expirar em menos de 30 dias. Se estiver
> interessado em renovar a sua licença, contacte
> [contact@tuist.dev](mailto:contact@tuist.dev).

### Configuração do ambiente de base {#base-environment-configuration}

| Variável de ambiente                  | Descrição                                                                                                                                                                                                                                                  | Necessário | Predefinição                       | Exemplos                                                                        |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | O URL de base para aceder à instância a partir da Internet                                                                                                                                                                                                 | Sim        |                                    | https://tuist.dev                                                               |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | A chave a utilizar para encriptar informações (por exemplo, sessões num cookie)                                                                                                                                                                            | Sim        |                                    |                                                                                 | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pimenta para gerar palavras-passe com hash                                                                                                                                                                                                                 | Não        | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Chave secreta para gerar tokens aleatórios                                                                                                                                                                                                                 | Não        | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | Chave de 32 bytes para encriptação AES-GCM de dados sensíveis                                                                                                                                                                                              | Não        | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | Quando `1` configura a aplicação para utilizar endereços IPv6                                                                                                                                                                                              | Não        | `0`                                | `1`                                                                             |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | O nível de registo a utilizar para a aplicação                                                                                                                                                                                                             | Não        | `informação`                       | [Níveis de registo](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | A chave privada codificada em base64 utilizada para a aplicação GitHub para desbloquear funcionalidades adicionais, como a publicação automática de comentários PR                                                                                         | Não        | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                                 |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | A chave privada utilizada para a aplicação GitHub para desbloquear funcionalidades extra, tais como a publicação automática de comentários PR. **Recomendamos a utilização da versão codificada em base64 para evitar problemas com caracteres especiais** | Não        | `-----BEGIN RSA...`                |                                                                                 |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | Uma lista separada por vírgulas de identificadores de utilizadores que têm acesso aos URLs das operações                                                                                                                                                   | Não        |                                    | `utilizador1,utilizador2`                                                       |                                                                                                                                    |
| `TUIST_WEB`                           | Ativar o ponto de extremidade do servidor Web                                                                                                                                                                                                              | Não        | `1`                                | `1` ou `0`                                                                      |                                                                                                                                    |

### Configuração da base de dados {#configuração da base de dados}

As seguintes variáveis de ambiente são utilizadas para configurar a ligação à
base de dados:

| Variável de ambiente                 | Descrição                                                                                                                                                                                                                                        | Necessário | Predefinição | Exemplos                                                               |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ------------ | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | O URL para aceder à base de dados Postgres. Note que o URL deve conter as informações de autenticação                                                                                                                                            | Sim        |              | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | O URL para aceder à base de dados do ClickHouse. Note que o URL deve conter as informações de autenticação                                                                                                                                       | Não        |              | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | Quando verdadeiro, utiliza [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) para estabelecer ligação à base de dados                                                                                                                | Não        | `1`          | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | O número de ligações a manter abertas no conjunto de ligações                                                                                                                                                                                    | Não        | `10`         | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | O intervalo (em milissegundos) para verificar se todas as ligações verificadas a partir do conjunto demoraram mais do que o intervalo da fila [(Mais informações)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Não        | `300`        | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | O tempo limite (em milissegundos) na fila de espera que o agrupamento utiliza para determinar se deve começar a eliminar novas ligações [(Mais informações)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)       | Não        | `1000`       | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | Intervalo de tempo em milissegundos entre as descargas da memória intermédia do ClickHouse                                                                                                                                                       | Não        | `5000`       | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | Tamanho máximo da memória intermédia do ClickHouse em bytes antes de forçar uma descarga                                                                                                                                                         | Não        | `1000000`    | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | Número de processos da memória intermédia do ClickHouse a executar                                                                                                                                                                               | Não        | `5`          | `5`                                                                    |

### Configuração do ambiente de autenticação {#authentication-environment-configuration}

Facilitamos a autenticação através de [fornecedores de identidade
(IdP)](https://en.wikipedia.org/wiki/Identity_provider). Para utilizar isso,
certifique-se de que todas as variáveis de ambiente necessárias para o provedor
escolhido estejam presentes no ambiente do servidor. **A falta de variáveis**
resultará no facto de o Tuist contornar esse fornecedor.

#### GitHub {#github}

Recomendamos a autenticação usando um [aplicativo
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps),
mas você também pode usar o [aplicativo
OAuth](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app).
Certifique-se de incluir todas as variáveis de ambiente essenciais especificadas
pelo GitHub no ambiente do servidor. A ausência de variáveis fará com que o
Tuist ignore a autenticação do GitHub. Para configurar corretamente o aplicativo
GitHub:
- Nas definições gerais da aplicação GitHub:
    - Copiar o `Client ID` e defini-lo como `TUIST_GITHUB_APP_CLIENT_ID`
    - Criar e copiar um novo segredo de cliente `` e defini-lo como
      `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Defina o URL de retorno de chamada `` como
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` também
      pode ser o endereço IP do seu servidor.
- São necessárias as seguintes permissões:
  - Repositórios:
    - Pedidos de transferência: Ler e escrever
  - Contas:
    - Endereços de correio eletrónico: Só de leitura

Na secção `Permissions and events`'s `Account permissions`, defina a permissão
`Email addresses` para `Read-only`.

Em seguida, é necessário expor as seguintes variáveis de ambiente no ambiente em
que o servidor Tuist é executado:

| Variável de ambiente             | Descrição                           | Necessário | Predefinição | Exemplos                                   |
| -------------------------------- | ----------------------------------- | ---------- | ------------ | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | O ID do cliente da aplicação GitHub | Sim        |              | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | O segredo do cliente da aplicação   | Sim        |              | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

Pode configurar a autenticação com o Google utilizando [OAuth
2](https://developers.google.com/identity/protocols/oauth2). Para tal, terá de
criar uma nova credencial do tipo ID de cliente OAuth. Ao criar as credenciais,
selecione "Aplicação Web" como tipo de aplicação, dê-lhe o nome `Tuist` e defina
o URI de redireccionamento para `{base_url}/users/auth/google/callback` onde
`base_url` é o URL em que o seu serviço alojado está a ser executado. Depois de
criar a aplicação, copie o ID e o segredo do cliente e defina-os como variáveis
de ambiente `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET` respetivamente.

> [Pode ser necessário criar um ecrã de consentimento. Quando o fizer,
> certifique-se de que adiciona os âmbitos `userinfo.email` e `openid` e marca a
> aplicação como interna.

#### Okta {#okta}

Pode ativar a autenticação com o Okta através do protocolo [OAuth
2.0](https://oauth.net/2/). Terá de [criar uma
aplicação](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
no Okta seguindo <LocalizedLink href="/guides/integrations/sso#okta">estas
instruções</LocalizedLink>.

Terá de definir as seguintes variáveis de ambiente depois de obter o ID e o
segredo do cliente durante a configuração da aplicação Okta:

| Variável de ambiente         | Descrição                                                                          | Necessário | Predefinição | Exemplos |
| ---------------------------- | ---------------------------------------------------------------------------------- | ---------- | ------------ | -------- |
| `TUIST_OKTA_1_CLIENT_ID`     | O ID do cliente para autenticar no Okta. O número deve ser o ID da sua organização | Sim        |              |          |
| `TUIST_OKTA_1_CLIENT_SECRET` | O segredo do cliente para autenticar no Okta                                       | Sim        |              |          |

O número `1` tem de ser substituído pelo ID da sua organização. Normalmente,
será 1, mas verifique na sua base de dados.

### Configuração do ambiente de armazenamento {#storage-environment-configuration}

O Tuist precisa de armazenamento para guardar os artefactos carregados através
da API. É **essencial configurar uma das soluções de armazenamento suportadas**
para que o Tuist funcione de forma eficaz.

#### Armazéns compatíveis com S3 {#s3compliant-storages}

É possível utilizar qualquer fornecedor de armazenamento compatível com S3 para
armazenar artefactos. As seguintes variáveis de ambiente são necessárias para
autenticar e configurar a integração com o fornecedor de armazenamento:

| Variável de ambiente                                 | Descrição                                                                                                                                   | Necessário | Predefinição                       | Exemplos                                   |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` ou `AWS_ACCESS_KEY_ID`         | O ID da chave de acesso para autenticar no fornecedor de armazenamento                                                                      | Sim        |                                    | `AKIAIOSFOD`                               |
| `TUIST_SECRET_ACCESS_KEY` ou `AWS_SECRET_ACCESS_KEY` | A chave de acesso secreta para autenticar contra o fornecedor de armazenamento                                                              | Sim        |                                    | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` ou `AWS_REGION`                    | A região onde o balde está localizado                                                                                                       | Não        | `automóvel`                        | `us-west-2`                                |
| `TUIST_S3_ENDPOINT` ou `AWS_ENDPOINT`                | O ponto de extremidade do fornecedor de armazenamento                                                                                       | Sim        |                                    | `https://s3.us-west-2.amazonaws.com`       |
| `TUIST_S3_BUCKET_NAME`                               | O nome do balde onde os artefactos serão armazenados                                                                                        | Sim        |                                    | `artefactos tuísticos`                     |
| `TUIST_S3_CONNECT_TIMEOUT`                           | O tempo limite (em milissegundos) para estabelecer uma ligação ao fornecedor de armazenamento                                               | Não        | `3000`                             | `3000`                                     |
| `TUIST_S3_RECEIVE_TIMEOUT`                           | O tempo limite (em milissegundos) para receber dados do fornecedor de armazenamento                                                         | Não        | `5000`                             | `5000`                                     |
| `TUIST_S3_POOL_TIMEOUT`                              | O tempo limite (em milissegundos) para o conjunto de ligações ao fornecedor de armazenamento. Utilize `infinito` para nenhum tempo limite   | Não        | `5000`                             | `5000`                                     |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                        | O tempo máximo de inatividade (em milissegundos) para ligações no grupo. Utilize `infinity` para manter as ligações activas indefinidamente | Não        | `infinito`                         | `60000`                                    |
| `TUIST_S3_POOL_SIZE`                                 | O número máximo de ligações por grupo                                                                                                       | Não        | `500`                              | `500`                                      |
| `TUIST_S3_POOL_COUNT`                                | O número de pools de ligação a utilizar                                                                                                     | Não        | Número de programadores do sistema | `4`                                        |
| `TUIST_S3_PROTOCOLO`                                 | O protocolo a utilizar na ligação ao fornecedor de armazenamento (`http1` ou `http2`)                                                       | Não        | `http1`                            | `http1`                                    |
| `TUIST_S3_VIRTUAL_HOST`                              | Se o URL deve ser construído com o nome do balde como um subdomínio (anfitrião virtual)                                                     | Não        | `falso`                            | `1`                                        |

> [!NOTE] Autenticação do AWS com o token de identidade da Web a partir de
> variáveis de ambiente Se o seu provedor de armazenamento for o AWS e você
> quiser se autenticar usando um token de identidade da Web, poderá definir a
> variável de ambiente `TUIST_S3_AUTHENTICATION_METHOD` para
> `aws_web_identity_token_from_env_vars`, e o Tuist usará esse método usando as
> variáveis de ambiente convencionais do AWS.

#### Armazenamento na nuvem do Google {#google-cloud-storage}
Para o Google Cloud Storage, siga [estes
documentos](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
para obter o par `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`. O `AWS_ENDPOINT`
deve ser definido como `https://storage.googleapis.com`. Outras variáveis de
ambiente são as mesmas que para qualquer outro armazenamento compatível com S3.

### Configuração da plataforma Git {#git-platform-configuration}

O Tuist pode <LocalizedLink href="/guides/server/authentication">integrar-se com
plataformas Git</LocalizedLink> para fornecer funcionalidades extra, tais como
publicar automaticamente comentários nos seus pedidos pull.

#### GitHub {#platform-github}

Terá de [criar uma aplicação
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
Pode reutilizar o que criou para autenticação, a menos que tenha criado uma
aplicação OAuth GitHub. Na secção `Permissões e eventos`'s `Permissões de
repositório`, terá de definir adicionalmente a permissão `Pull requests` para
`Ler e escrever`.

Para além de `TUIST_GITHUB_APP_CLIENT_ID` e `TUIST_GITHUB_APP_CLIENT_SECRET`,
são necessárias as seguintes variáveis de ambiente:

| Variável de ambiente           | Descrição                           | Necessário | Predefinição | Exemplos                             |
| ------------------------------ | ----------------------------------- | ---------- | ------------ | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | A chave privada da aplicação GitHub | Sim        |              | `-----BEGIN RSA PRIVATE KEY-----...` |

## Implementação {#deployment}

A imagem oficial do Tuist Docker está disponível em:
```
ghcr.io/tuist/tuist
```

### Puxando a imagem do Docker {#pulling-the-docker-image}

Pode recuperar a imagem executando o seguinte comando:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Ou selecionar uma versão específica:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Implementar a imagem do Docker {#deploying-the-docker-image}

O processo de implantação da imagem do Docker será diferente com base no
provedor de nuvem escolhido e na abordagem de implantação contínua da sua
organização. Uma vez que a maioria das soluções e ferramentas de nuvem, como
[Kubernetes](https://kubernetes.io/), utilizam imagens Docker como unidades
fundamentais, os exemplos nesta secção devem alinhar-se bem com a sua
configuração existente.

> [IMPORTANTE] Se o seu pipeline de implantação precisar de validar que o
> servidor está a funcionar, pode enviar um pedido HTTP `GET` para `/ready` e
> afirmar um código de estado `200` na resposta.

#### Voar

Para implantar o aplicativo em [Fly](https://fly.io/), você precisará de um
arquivo de configuração `fly.toml`. Considere a possibilidade de gerá-lo
dinamicamente no pipeline de implantação contínua (CD). Abaixo está um exemplo
de referência para seu uso:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Depois, pode executar `fly launch --local-only --no-deploy` para lançar a
aplicação. Em implantações subsequentes, em vez de executar `fly launch
--local-only`, você precisará executar `fly deploy --local-only`. O Fly.io não
permite extrair imagens Docker privadas, e é por isso que precisamos usar o
sinalizador `--local-only`.

### Docker Compose {#docker-compose}

Abaixo está um exemplo de um arquivo `docker-compose.yml` que pode ser usado
como referência para implantar o serviço:

```yaml
version: '3.8'
services:
  db:
    image: timescale/timescaledb-ha:pg16
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - PGDATA=/var/lib/postgresql/data/pgdata
    ports:
      - '5432:5432'
    volumes:
      - db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgweb:
    container_name: pgweb
    restart: always
    image: sosedoff/pgweb
    ports:
      - "8081:8081"
    links:
      - db:db
    environment:
      PGWEB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
    depends_on:
      - db

  tuist:
    image: ghcr.io/tuist/tuist:latest
    container_name: tuist
    depends_on:
      - db
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    expose:
      - "80"
      - "8080"
      - "443:443"
    environment:
      # Base Tuist Env - https://docs.tuist.io/en/guides/dashboard/on-premise/install#base-environment-configuration
      TUIST_USE_SSL_FOR_DATABASE: "0"
      TUIST_LICENSE:  # ...
      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
      TUIST_APP_URL: https://localhost:8080
      TUIST_SECRET_KEY_BASE: # ...
      WEB_CONCURRENCY: 80

      # Auth - one method
      # GitHub Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#github
      TUIST_GITHUB_OAUTH_ID:
      TUIST_GITHUB_APP_CLIENT_SECRET:

      # Okta Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#okta
      TUIST_OKTA_SITE:
      TUIST_OKTA_CLIENT_ID:
      TUIST_OKTA_CLIENT_SECRET:
      TUIST_OKTA_AUTHORIZE_URL: # Optional
      TUIST_OKTA_TOKEN_URL: # Optional
      TUIST_OKTA_USER_INFO_URL: # Optional
      TUIST_OKTA_EVENT_HOOK_SECRET: # Optional

      # Storage
      AWS_ACCESS_KEY_ID: # ...
      AWS_SECRET_ACCESS_KEY: # ...
      AWS_S3_REGION: # ...
      AWS_ENDPOINT: # https://amazonaws.com
      TUIST_S3_BUCKET_NAME: # ...

      # Other

volumes:
  db:
    driver: local
```

## Métricas do Prometheus {#prometheus-metrics}

O Tuist expõe as métricas do Prometheus em `/metrics` para o ajudar a
monitorizar a sua instância auto-hospedada. Essas métricas incluem:

### Métricas do cliente HTTP Finch {#finch-metrics}

O Tuist utiliza o [Finch](https://github.com/sneako/finch) como cliente HTTP e
expõe métricas detalhadas sobre os pedidos HTTP:

#### Solicitar métricas
- `tuist_prom_ex_finch_request_count_total` - Número total de pedidos Finch
  (contador)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Duração dos pedidos HTTP
  (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Baldes: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Número total de
  excepções de pedidos Finch (contador)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`,
    `reason`

#### Métricas da fila do pool de ligações
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Tempo de espera na fila do
  grupo de ligações (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Baldes: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Tempo que a ligação
  passou inativa antes de ser utilizada (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Baldes: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Número total de excepções
  da fila Finch (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Métricas de ligação
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Tempo gasto a
  estabelecer uma ligação (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `error`
  - Baldes: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Número total de tentativas de
  ligação (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`

#### Enviar métricas
- `tuist_prom_ex_finch_send_duration_milliseconds` - Tempo gasto a enviar o
  pedido (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Baldes: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Tempo que a ligação passou
  inativa antes de enviar (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Baldes: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Todas as métricas de histograma fornecem as variantes `_bucket`, `_sum` e
`_count` para uma análise detalhada.

### Outras métricas

Para além das métricas Finch, o Tuist expõe métricas para:
- Desempenho da máquina virtual BEAM
- Métricas de lógica empresarial personalizadas (armazenamento, contas,
  projectos, etc.)
- Desempenho da base de dados (quando se utiliza a infraestrutura alojada pela
  Tuist)

## Operações {#operações}

O Tuist fornece um conjunto de utilitários em `/ops/` que pode utilizar para
gerir a sua instância.

> [!IMPORTANTE] Autorização Apenas as pessoas cujos identificadores estão
> listados na variável de ambiente `TUIST_OPS_USER_HANDLES` podem aceder aos
> pontos finais `/ops/`.

- **Erros (`/ops/errors`):** Pode visualizar erros inesperados que ocorreram na
  aplicação. Isto é útil para depurar e compreender o que correu mal e podemos
  pedir-lhe que partilhe esta informação connosco se estiver a enfrentar
  problemas.
- **Dashboard (`/ops/dashboard`):** É possível visualizar um painel que fornece
  informações sobre o desempenho e a integridade do aplicativo (por exemplo,
  consumo de memória, processos em execução, número de solicitações). Este
  painel de controlo pode ser bastante útil para perceber se o hardware que está
  a utilizar é suficiente para lidar com a carga.
