---
{
  "title": "Kod paylaşımı",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tekrarları azaltmak ve tutarlılığı sağlamak için kodun bildirim dosyaları arasında nasıl paylaşılacağını öğrenin"
}
---
# Kod paylaşımı {#code-sharing}

Büyük projelerde Xcode kullanırken yaşanan sıkıntılardan biri, derleme ayarları dışında proje öğelerinin `.xcconfig` dosyaları aracılığıyla yeniden kullanılmasına izin vermemesidir. Proje tanımlarını yeniden kullanabilmek aşağıdaki nedenlerle faydalıdır:

- Değişiklikler tek bir yerde uygulanabilir ve tüm projeler bu değişiklikleri otomatik olarak aldığı için **bakımı** kolaylaştırır.
- Yeni projelerin uyabileceği **kurallar** tanımlamayı mümkün kılar.
- Projeler daha **tutarlı** hale gelir ve bu nedenle tutarsızlıklardan kaynaklanan başarısız derlemelerin olasılığı önemli ölçüde azalır.
- Mevcut mantığı yeniden kullanabildiğimiz için yeni projeler eklemek kolay bir görev haline gelir.

Manifest dosyaları arasında kodun yeniden kullanılması, Tuist'te **proje açıklama yardımcıları** kavramı sayesinde mümkündür.

> [!TIP]
> **Tuist'e özgü bir avantaj**
>
> Birçok kuruluş, proje açıklama yardımcılarında platform ekiplerinin kendi kurallarını kodlaması ve projelerini tanımlamak için kendi dillerini geliştirmesi için bir platform gördüğü için Tuist'i tercih eder. Örneğin, YAML tabanlı proje oluşturucuların kendi YAML tabanlı özel şablonlama çözümlerini geliştirmesi veya kuruluşları araçlarını bunun üzerine inşa etmeye zorlaması gerekir.


## Proje açıklama yardımcıları {#project-description-helpers}

Proje açıklama yardımcıları, manifest dosyalarının içe aktarabileceği `ProjectDescriptionHelpers` adlı bir modüle derlenen Swift dosyalarıdır. Modül, `Tuist/ProjectDescriptionHelpers` dizinindeki tüm dosyalar toplanarak derlenir.

Dosyanın başına bir import ifadesi ekleyerek bunları manifest dosyanıza içe aktarabilirsiniz:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` aşağıdaki manifestlerde kullanılabilir:
- `Project.swift`
- `Package.swift` (yalnızca `#TUIST` derleyici bayrağı etkin olduğunda)
- `Workspace.swift`

## Örnek {#example}

Aşağıdaki kod parçacıkları, statik oluşturucular eklemek için `Project` modelini nasıl genişlettiğimizi ve bunları bir `Project.swift` dosyasından nasıl kullandığımızı gösteren bir örnek içerir:

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

> [!TIP]
> **Kuralları belirlemek için bir araç**
>
> Fonksiyon aracılığıyla hedeflerin adları, paket kimliği ve klasör yapısı hakkında kurallar tanımladığımıza dikkat edin.
