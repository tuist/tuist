---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Usando o Tuist com um pacote Swift <Badge type="warning" text="beta" /> {#usando-tuist-com-um-pacote-swift-badge-typewarning-textbeta-}

O Tuist suporta o uso do `Package.swift` como uma DSL para seus projetos e
converte seus alvos de pacote em um projeto e alvos nativos do Xcode.

> [O objetivo deste recurso é fornecer uma maneira fácil para os desenvolvedores
> avaliarem o impacto da adoção do Tuist em seus pacotes Swift. Portanto, nós
> não planejamos suportar toda a gama de recursos do Swift Package Manager nem
> trazer todos os recursos exclusivos do Tuist como
> <LocalizedLink href="/guides/features/projects/code-sharing">project
> description helpers</LocalizedLink> para o mundo dos pacotes.

> [Os comandos Tuist esperam uma certa estrutura de diretórios
> <LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects"></LocalizedLink>
> cuja raiz é identificada por um `Tuist` ou um diretório `.git`.

## Usando o Tuist com um pacote Swift {#usando-tuist-com-um-pacote-swift}

Vamos usar o Tuist com o repositório [TootSDK
Package](https://github.com/TootSDK/TootSDK), que contém um pacote Swift. A
primeira coisa que precisamos fazer é clonar o repositório:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Uma vez no diretório do repositório, precisamos instalar as dependências do
Swift Package Manager:

```bash
tuist install
```

Sob o capô `tuist install` usa o Swift Package Manager para resolver e puxar as
dependências do pacote. Depois que a resolução for concluída, você poderá gerar
o projeto:

```bash
tuist generate
```

Voilà! Tem um projeto Xcode nativo que pode abrir e no qual pode começar a
trabalhar.
