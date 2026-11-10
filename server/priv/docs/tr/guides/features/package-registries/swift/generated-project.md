---
{
  "title": "Xcode paket entegrasyonlu oluşturulmuş proje",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode paket entegrasyonlu bir Xcode projesinde Tuist Registry'nin nasıl kullanılacağını öğrenin."
}
---
# Xcode paket entegrasyonu ile oluşturulan proje {#generated-project-with-xcode-based-integration}

Tuist Projeleri ile paketlerin <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">Xcode'un varsayılan entegrasyonunu</.localized_link> kullanıyorsanız, bir paket eklerken URL yerine kayıt tanımlayıcısını kullanmanız gerekir:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```

> [!TIP]
> Her paketi kayıt tanımlayıcısıyla eklemek zorunda değilsiniz. Proje oluşturulduktan sonra `tuist registry setup` komutunu çalıştırmak, Xcode'u kaynak kontrol URL'siyle bildirilen paketleri kayıt üzerinden çözümleyecek şekilde de yapılandırır; bu işlemi `registryEnabled` tek başına yapmaz. Bkz. <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Kaynak kontrol paketlerinin çözülmesi</.localized_link>.
