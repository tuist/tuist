---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Autenticação {#authentication}

Para interagir com o servidor, a CLI precisa de autenticar os pedidos utilizando
[autenticação de
portador](https://swagger.io/docs/specification/authentication/bearer-authentication/).
O CLI suporta a autenticação como utilizador ou como projeto.

## Como utilizador {#como utilizador}

Quando utilizar o CLI localmente no seu computador, recomendamos a autenticação
como utilizador. Para se autenticar como utilizador, é necessário executar o
seguinte comando:

```bash
tuist auth login
```

O comando conduzi-lo-á através de um fluxo de autenticação baseado na Web. Após
a autenticação, a CLI armazenará um token de atualização de longa duração e um
token de acesso de curta duração em `~/.config/tuist/credentials`. Cada ficheiro
no diretório representa o domínio em que se autenticou, que por predefinição
deve ser `tuist.dev.json`. As informações armazenadas nesse diretório são
sensíveis, por isso **certifique-se de que as mantém seguras**.

A CLI procurará automaticamente as credenciais quando efetuar pedidos ao
servidor. Se o token de acesso tiver expirado, o CLI utilizará o token de
atualização para obter um novo token de acesso.

## Como um projeto {#como um projeto}

Em ambientes não interactivos, como as integrações contínuas, não é possível
autenticar através de um fluxo interativo. Para esses ambientes, recomendamos a
autenticação como um projeto usando um token com escopo de projeto:

```bash
tuist project tokens create
```

A CLI espera que o token seja definido como a variável de ambiente
`TUIST_CONFIG_TOKEN`, e que a variável de ambiente `CI=1` seja definida. A CLI
utilizará o token para autenticar os pedidos.

> [IMPORTANTE] ESCOPO LIMITADO As permissões do token com escopo de projeto são
> limitadas às ações que consideramos seguras para os projetos executarem a
> partir de um ambiente de CI. Planeamos documentar as permissões que o token
> tem no futuro.
