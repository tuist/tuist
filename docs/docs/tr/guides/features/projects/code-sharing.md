---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Kod paylaşımı {#code-sharing}

Xcode'u büyük projelerde kullanırken karşılaştığımız zorluklardan biri,
`.xcconfig` dosyaları aracılığıyla yapı ayarları dışındaki proje öğelerinin
yeniden kullanılmasına izin vermemesidir. Proje tanımlarını yeniden
kullanabilmek aşağıdaki nedenlerden dolayı yararlıdır:

- Değişiklikler tek bir yerde uygulanabildiği ve tüm projeler değişiklikleri
  otomatik olarak aldığı için **bakımını** kolaylaştırır.
- Bu, yeni projelerin uyum sağlayabileceği **kuralları** tanımlamayı mümkün
  kılar.
- Projeler daha tutarlıdır **** ve bu nedenle tutarsızlıklar nedeniyle bozuk
  derlemeler olasılığı önemli ölçüde azalır.
- Mevcut mantığı yeniden kullanabileceğimiz için yeni projeler eklemek kolay bir
  iş haline gelir.

Tuist'te, **proje açıklaması yardımcıları** konsepti sayesinde manifest
dosyalarında kodların yeniden kullanılması mümkündür.

::: tip A TUIST UNIQUE ASSET
<!-- -->
Birçok kuruluş, proje açıklaması yardımcılarında platform ekiplerinin kendi
kurallarını kodlayabilecekleri ve projelerini tanımlamak için kendi dillerini
oluşturabilecekleri bir platform gördükleri için Tuist'i seviyor. Örneğin, YAML
tabanlı proje oluşturucular, kendi YAML tabanlı özel şablon çözümlerini
geliştirmek veya kuruluşları kendi araçlarını oluşturmaya zorlamak zorundadır.
<!-- -->
:::

## Proje açıklaması yardımcıları {#project-description-helpers}

Proje açıklaması yardımcıları, manifest dosyalarının içe aktarabileceği bir
modüle derlenen Swift dosyalarıdır: `ProjectDescriptionHelpers`. Modül,
`Tuist/ProjectDescriptionHelpers` dizinindeki tüm dosyalar toplanarak derlenir.

Dosyanın en üstüne bir içe aktarma ifadesi ekleyerek bunları manifest dosyanıza
içe aktarabilirsiniz:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` aşağıdaki manifestolarda mevcuttur:
- `Project.swift`
- `Package.swift` (yalnızca `#TUIST` derleyici bayrağının arkasında)
- `Workspace.swift`

## Örnek {#example}

Aşağıdaki kod parçacıkları, `Project` modelini statik yapıcılar eklemek için
nasıl genişlettiğimize ve bunları `Project.swift` dosyasından nasıl
kullandığımıza dair bir örnek içerir:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
Bu işlev aracılığıyla hedeflerin adı, paket tanımlayıcı ve klasör yapısı
hakkında kurallar tanımladığımızı unutmayın.
<!-- -->
:::
