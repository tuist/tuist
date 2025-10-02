---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Projeto gerado com a integração de pacotes baseada no XcodeProj {#generated-project-with-xcodeproj-based-integration}

Ao usar a integração baseada no
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj</LocalizedLink>,
é possível usar o sinalizador ``--replace-scm-with-registry`` para resolver
dependências do registro, se elas estiverem disponíveis. Adicione-o a
`installOptions` em seu arquivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Se quiser garantir que o registo é utilizado sempre que resolve dependências,
terá de atualizar `dependencies` no seu ficheiro `Tuist/Package.swift` para
utilizar o identificador do registo em vez de um URL. O identificador do registo
tem sempre a forma de `{organização}.{repositório}`. Por exemplo, para usar o
registro para o pacote `swift-composable-architecture`, faça o seguinte:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
