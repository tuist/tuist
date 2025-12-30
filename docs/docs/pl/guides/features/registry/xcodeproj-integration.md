---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Wygenerowany projekt z integracją pakietów opartą na XcodeProj {#generated-project-with-xcodeproj-based-integration}

Podczas korzystania z integracji opartej na
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj</LocalizedLink>
można użyć flagi ``--replace-scm-with-registry``, aby rozwiązać zależności z
rejestru, jeśli są one dostępne. Dodaj ją do pola `installOptions` w pliku
`Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
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
