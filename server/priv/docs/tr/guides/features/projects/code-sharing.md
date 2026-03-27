---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Kod paylaşımı {#code-sharing}

Xcode'u büyük projelerle kullandığımızda karşılaştığımız sorunlardan biri,
`.xcconfig` dosyaları aracılığıyla derleme ayarları dışında projelerin
öğelerinin yeniden kullanılmasına izin vermemesidir. Proje tanımlarını yeniden
kullanabilmek aşağıdaki nedenlerden dolayı yararlıdır:

- Değişiklikler tek bir yerde uygulanabildiği ve tüm projeler değişiklikleri
  otomatik olarak aldığı için **bakımını** kolaylaştırır.
- Yeni projelerin uyabileceği **sözleşmelerinin** tanımlanmasını mümkün kılar.
- Projeler daha **tutarlı** ve bu nedenle tutarsızlıklar nedeniyle bozuk derleme
  olasılığı önemli ölçüde daha az.
- Mevcut mantığı yeniden kullanabildiğimiz için yeni bir proje eklemek kolay bir
  iş haline gelir.

Tuist'te **proje açıklama yardımcıları** kavramı sayesinde manifesto dosyaları
arasında kodun yeniden kullanılması mümkündür.

::: tip A TUIST UNIQUE ASSET
<!-- -->
Birçok kuruluş Tuist'i seviyor çünkü proje tanımlama yardımcılarında, platform
ekiplerinin kendi kurallarını kodlamaları ve projelerini tanımlamak için kendi
dillerini bulmaları için bir platform görüyorlar. Örneğin, YAML tabanlı proje
oluşturucuların kendi YAML tabanlı özel şablonlama çözümlerini bulmaları ya da
kuruluşları araçlarını bunun üzerine inşa etmeye zorlamaları gerekiyor.
<!-- -->
:::

## Proje açıklama yardımcıları {#project-description-helpers}

Proje açıklama yardımcıları, manifesto dosyalarının içe aktarabileceği bir modül
olan `ProjectDescriptionHelpers` içinde derlenen Swift dosyalarıdır. Modül,
`Tuist/ProjectDescriptionHelpers` dizinindeki tüm dosyalar bir araya getirilerek
derlenir.

Dosyanın üst kısmına bir içe aktarma ifadesi ekleyerek bunları manifesto
dosyanıza aktarabilirsiniz:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` aşağıdaki manifestolarda mevcuttur:
- `Proje.swift`
- `Package.swift` (sadece `#TUIST` derleyici bayrağının arkasında)
- `Çalışma Alanı.swift`

## Örnek {#example}

Aşağıdaki parçacıklar, statik kurucular eklemek için `Project` modelini nasıl
genişlettiğimizi ve bunları bir `Project.swift` dosyasından nasıl kullandığımızı
gösteren bir örnek içerir:

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
İşlev aracılığıyla hedeflerin adı, paket tanımlayıcısı ve klasör yapısı hakkında
nasıl kurallar tanımladığımıza dikkat edin.
<!-- -->
:::
