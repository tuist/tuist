---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Contas e projectos {#contas-e-projectos}

Algumas funcionalidades Tuist requerem um servidor que adiciona persistência de
dados e pode interagir com outros serviços. Para interagir com o servidor, é
necessária uma conta e um projeto que se liga ao seu projeto local.

## Contas {#accounts}

Para utilizar o servidor, precisa de uma conta. Existem dois tipos de contas:

- **Conta pessoal:** Estas contas são criadas automaticamente quando o
  utilizador se inscreve e são identificadas por um identificador que é obtido a
  partir do fornecedor de identidade (por exemplo, GitHub) ou da primeira parte
  do endereço de correio eletrónico.
- **Conta da organização:** Estas contas são criadas manualmente e são
  identificadas por um identificador definido pelo programador. As organizações
  permitem convidar outros membros para colaborar em projectos.

Se estiver familiarizado com o [GitHub](https://github.com), o conceito é
semelhante ao deles, em que é possível ter contas pessoais e de organizações, e
estas são identificadas por um identificador ** que é utilizado na construção de
URLs.

> [A maioria das operações de gestão de contas e projectos é efectuada através
> do CLI. Estamos a trabalhar numa interface Web que facilitará a gestão de
> contas e projectos.

Pode gerir a organização através dos subcomandos em
<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>.
Para criar uma nova conta de organização, execute:
```bash
tuist organization create {account-handle}
```

## Projectos {#projectos}

Os seus projectos, quer do Tuist quer do Xcode em bruto, têm de ser integrados
na sua conta através de um projeto remoto. Continuando com a comparação com o
GitHub, é como ter um repositório local e um repositório remoto para onde se
enviam as alterações. Pode utilizar o projeto
<LocalizedLink href="/cli/project">`tuist`</LocalizedLink> para criar e gerir
projectos.

Os projectos são identificados por um identificador completo, que é o resultado
da concatenação do identificador da organização e do identificador do projeto.
Por exemplo, se tiver uma organização com o identificador `tuist`, e um projeto
com o identificador `tuist`, o identificador completo será `tuist/tuist`.

A ligação entre o projeto local e o remoto é feita através do ficheiro de
configuração. Se não tiver nenhum, crie-o em `Tuist.swift` e adicione o seguinte
conteúdo:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [IMPORTANTE] RECURSOS APENAS DO PROJETO TUIST Observe que há alguns recursos
> como <LocalizedLink href="/guides/features/cache">cache
> binário</LocalizedLink> que exigem que você tenha um projeto Tuist. Se estiver
> a utilizar projectos Xcode em bruto, não poderá utilizar essas
> funcionalidades.

O URL do seu projeto é construído utilizando o identificador completo. Por
exemplo, o painel de controlo do Tuist, que é público, está acessível em
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), onde `tuist/tuist` é o
identificador completo do projeto.
