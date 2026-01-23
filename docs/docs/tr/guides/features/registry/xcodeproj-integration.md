---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# XcodeProj tabanlı paket entegrasyonu ile oluşturulmuş projele {#generated-project-with-xcodeproj-based-integration}

<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj
tabanlı entegrasyon</LocalizedLink> kullanırken, kayıtta mevcutsa bağımlılıkları
çözmek için ``--replace-scm-with-registry`` bayrağını kullanabilirsiniz. Bunu
`installOptions` dosyasına `Tuist.swift` dosyasına ekleyin:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Bağımlılıkları her çözdüğünüzde kayıt defterinin kullanılmasını sağlamak
istiyorsanız, `Tuist/Package.swift` dosyanızdaki `dependencies` bölümünü, URL
yerine kayıt defteri tanımlayıcısını kullanacak şekilde güncellemeniz gerekir.
Kayıt defteri tanımlayıcısı her zaman `{organization}.{repository}`
biçimindedir. Örneğin, `swift-composable-architecture` paketinin kayıt defterini
kullanmak için aşağıdakileri yapın:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
