---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGen projesini taşıma {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), Xcode projelerini tanımlamak
için [bir yapılandırma
biçimi](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
olarak YAML kullanan bir proje oluşturma aracıdır. Birçok kuruluş **, Xcode
projeleriyle çalışırken sık sık ortaya çıkan Git çakışmalarından kurtulmak için
bu aracı benimsemiştir.** Ancak, sık sık ortaya çıkan Git çakışmaları,
kuruluşların karşılaştığı birçok sorundan sadece biridir. Xcode,
geliştiricilere, projelerin büyük ölçekte bakımını ve optimizasyonunu
zorlaştıran birçok karmaşık ve örtük yapılandırma sunar. XcodeGen, bir proje
yöneticisi değil, Xcode projeleri oluşturan bir araç olduğu için bu konuda
yetersiz kalır. Xcode projeleri oluşturmanın ötesinde size yardımcı olacak bir
araca ihtiyacınız varsa, Tuist'i düşünebilirsiniz.

::: tip SWIFT OVER YAML
<!-- -->
Birçok kuruluş, yapılandırma biçimi olarak Swift kullandığı için Tuist'i proje
oluşturma aracı olarak da tercih etmektedir. Swift, geliştiricilerin aşina
olduğu bir programlama dilidir ve onlara Xcode'un otomatik tamamlama, tür
denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.
<!-- -->
:::

Aşağıda, projelerinizi XcodeGen'den Tuist'e taşıma konusunda size yardımcı
olacak bazı hususlar ve yönergeler yer almaktadır.

## Proje oluşturma {#project-generation}

Hem Tuist hem de XcodeGen, proje beyanınızı Xcode projeleri ve çalışma
alanlarına dönüştüren `generate` komutunu sağlar.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Fark, düzenleme deneyiminde yatmaktadır. Tuist ile, `tuist edit` komutunu
çalıştırabilirsiniz. Bu komut, açıp üzerinde çalışmaya başlayabileceğiniz bir
Xcode projesini anında oluşturur. Bu, projenizde hızlı değişiklikler yapmak
istediğinizde özellikle kullanışlıdır.

## `project.yaml` {#projectyaml}

XcodeGen'in `project.yaml` açıklama dosyası, `Project.swift` haline gelir.
Ayrıca, projelerin çalışma alanlarında nasıl gruplandırılacağını özelleştirmek
için `Workspace.swift` dosyasını kullanabilirsiniz. Diğer projelerden hedefleri
referans alan hedefleri içeren bir proje `Project.swift` de oluşturabilirsiniz.
Bu durumlarda Tuist, tüm projeleri içeren bir Xcode Çalışma Alanı oluşturur.

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

::: tip XCODE'S LANGUAGE
<!-- -->
Hem XcodeGen hem de Tuist, Xcode'un dilini ve kavramlarını benimser. Ancak,
Tuist'in Swift tabanlı yapılandırması, Xcode'un otomatik tamamlama, tür denetimi
ve doğrulama özelliklerini kullanma kolaylığı sağlar.
<!-- -->
:::

## Özellik şablonları {#spec-templates}

Proje yapılandırması için bir dil olarak YAML'ın dezavantajlarından biri, YAML
dosyaları arasında yeniden kullanılabilirliği desteklememesidir. Bu, projeleri
tanımlarken sıkça karşılaşılan bir ihtiyaçtır ve XcodeGen, bunu kendi özel
çözümü olan *"şablonları"* ile çözmek zorunda kalmıştır. Tuist'te yeniden
kullanılabilirlik, dilin kendisi olan Swift'e ve
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklaması
yardımcıları</LocalizedLink> adlı bir Swift modülüne entegre edilmiştir, bu da
tüm manifest dosyalarınızda kodun yeniden kullanılmasını sağlar.

::: code-group
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
