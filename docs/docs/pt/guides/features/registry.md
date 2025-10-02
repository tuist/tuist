---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Registo {#registo}

> REQUISITOS [!IMPORTANTE]
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

Conforme o número de dependências cresce, também cresce o tempo para
resolvê-las. Enquanto outros gerenciadores de pacotes como
[CocoaPods](https://cocoapods.org/) ou [npm](https://www.npmjs.com/) são
centralizados, o Swift Package Manager não é. Por causa disso, o SwiftPM precisa
resolver dependências fazendo um clone profundo de cada repositório, o que pode
ser demorado e ocupa mais memória do que uma abordagem centralizada faria. Para
resolver isto, o Tuist fornece uma implementação do [Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md),
para que possa descarregar apenas os commits que _realmente precisa_. Os pacotes
no registo são baseados no [Swift Package Index](https://swiftpackageindex.com/)
- se você pode encontrar um pacote lá, o pacote também está disponível no
Registro Tuist. Além disso, os pacotes são distribuídos por todo o mundo usando
um armazenamento de borda para uma latência mínima ao resolvê-los.

## Utilização {#usage}

Para configurar e iniciar sessão no registo, execute o seguinte comando no
diretório do seu projeto:

```bash
tuist registry setup
```

Este comando gera um ficheiro de configuração do registo e inicia sessão no
registo. Para garantir que o resto da sua equipa pode aceder ao registo,
certifique-se de que os ficheiros gerados são confirmados e que os membros da
sua equipa executam o seguinte comando para iniciar sessão:

```bash
tuist registry login
```

Agora já pode aceder ao registo! Para resolver dependências a partir do registo
em vez de a partir do controlo de origem, continue a ler com base na
configuração do seu projeto:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  project</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Projeto
  gerado com a integração do pacote Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Projeto
  gerado com a integração de pacotes baseada no XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift
  package</LocalizedLink>

Para configurar o registo na IC, siga este guia: {Integração contínua

### Identificadores de registo de pacotes {#package-registry-identifiers}

Quando utiliza identificadores do registo de pacotes num ficheiro
`Package.swift` ou `Project.swift`, tem de converter o URL do pacote para a
convenção do registo. O identificador de registo tem sempre a forma de
`{organização}.{repositório}`. Por exemplo, para utilizar o registo para o
pacote `https://github.com/pointfreeco/swift-composable-architecture`, o
identificador de registo do pacote seria
`pointfreeco.swift-composable-architecture`.

> [O identificador não pode conter mais do que um ponto. Se o nome do
> repositório contiver um ponto, ele será substituído por um sublinhado. Por
> exemplo, o pacote `https://github.com/groue/GRDB.swift` teria o identificador
> de registo `groue.GRDB_swift`.
