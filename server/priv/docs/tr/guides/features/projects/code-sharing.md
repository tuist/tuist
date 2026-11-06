---
{
  "title": "Kod paylaşımı",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tekrarları azaltmak ve tutarlılığı sağlamak için kodu bildirim dosyaları arasında nasıl paylaşacağınızı öğrenin"
}
---
# Kod paylaşımı {#code-sharing}

Büyük projelerde Xcode kullanırken karşılaşılan zorluklardan biri, derleme ayarları dışında proje öğelerinin `.xcconfig` dosyaları aracılığıyla yeniden kullanılmasına izin vermemesidir. Proje tanımlarını yeniden kullanabilmek aşağıdaki nedenlerle faydalıdır:

- Değişiklikler tek bir yerde uygulanabilir ve tüm projeler bu değişiklikleri otomatik olarak aldığı için **bakım** kolaylaşır.
- Yeni projelerin uyabileceği **kurallar** tanımlamayı mümkün kılar.
- Projeler daha **tutarlı** hale gelir ve bu nedenle tutarsızlıklardan kaynaklanan başarısız derlemelerin olasılığı önemli ölçüde azalır.
- Mevcut mantığı yeniden kullanabildiğimiz için yeni projeler eklemek kolay bir iş haline gelir.

Manifest dosyaları arasında kodun yeniden kullanılması, Tuist'te **proje açıklama yardımcıları** kavramı sayesinde mümkündür.

> [!TIP]
> **Tuist'e özgü bir avantaj**
>
> Birçok kuruluş, proje açıklama yardımcılarında platform ekiplerinin kendi kurallarını kodlayıp projelerini tanımlamak için kendi dillerini geliştirebilecekleri bir platform gördükleri için Tuist'i tercih eder. Örneğin, YAML tabanlı proje oluşturucular kendi YAML tabanlı özel şablonlama çözümlerini geliştirmek zorunda kalır veya kuruluşları araçlarını bunun üzerine inşa etmeye zorlar.


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
- `Package.swift` (yalnızca `#TUIST` derleyici bayrağı etkinleştirildiğinde)
- `Workspace.swift`

## Örnek {#example}

Aşağıdaki kod parçacıkları, statik yapıcılar eklemek için `Project` modelini nasıl genişlettiğimizi ve bunları bir `Project.swift` dosyasından nasıl kullandığımızı gösteren bir örnek içerir:

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
> Fonksiyon aracılığıyla hedeflerin adı, paket kimliği ve klasör yapısı hakkında kurallar tanımladığımıza dikkat edin.
