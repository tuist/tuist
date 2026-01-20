---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Pakiet Swift {#swift-package}

Jeśli pracujesz nad pakietem Swift, możesz użyć flagi
`--replace-scm-with-registry`, aby rozwiązać zależności z rejestru, jeśli są one
dostępne:

```bash
swift package --replace-scm-with-registry resolve
```

Jeśli chcesz upewnić się, że rejestr jest używany za każdym razem, gdy
rozwiązujesz zależności, musisz zaktualizować zależności `` w pliku
`Tuist/Package.swift`, aby używać identyfikatora rejestru zamiast adresu URL.
Identyfikator rejestru ma zawsze postać `{organization}.{repository}`. Na
przykład, aby użyć rejestru dla pakietu `swift-composable-architecture`, wykonaj
następujące czynności:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
