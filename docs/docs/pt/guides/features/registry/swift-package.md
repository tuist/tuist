---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Pacote Swift {#swift-package}

Se estiver a trabalhar num pacote Swift, pode utilizar a flag
`--replace-scm-with-registry` para resolver dependências do registo se estiverem
disponíveis:

```bash
swift package --replace-scm-with-registry resolve
```

Se quiser garantir que o registo é utilizado sempre que resolve dependências,
terá de atualizar `dependencies` no seu ficheiro `Package.swift` para utilizar o
identificador do registo em vez de um URL. O identificador do registo tem sempre
a forma de `{organização}.{repositório}`. Por exemplo, para usar o registro para
o pacote `swift-composable-architecture`, faça o seguinte:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
