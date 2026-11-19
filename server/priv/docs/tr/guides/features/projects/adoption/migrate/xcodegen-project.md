---
{
  "title": "XcodeGen projesini taşıma",
  "titleTemplate": ":title · Taşıma · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizi XcodeGen'den Tuist'e nasıl taşıyacağınızı öğrenin."
}
---
# Bir XcodeGen projesini taşıma {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), Xcode projelerini tanımlamak için yapılandırma formatı olarak [YAML kullanan](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) bir proje oluşturma aracıdır. Birçok kuruluş, **Xcode projeleriyle çalışırken ortaya çıkan sık Git çakışmalarından kurtulmak amacıyla bu aracı benimsedi.** Ancak sık yaşanan Git çakışmaları, kuruluşların karşılaştığı birçok sorundan yalnızca biridir. Xcode, geliştiricilere projeleri büyük ölçekte sürdürmeyi ve optimize etmeyi zorlaştıran çok sayıda karmaşıklık ve örtük yapılandırma sunar. XcodeGen, Xcode projeleri üreten bir araç olup bir proje yöneticisi olmadığından bu konuda tasarım gereği yetersiz kalır. Xcode projeleri oluşturmanın ötesinde size yardımcı olacak bir araca ihtiyacınız varsa Tuist'i değerlendirmek isteyebilirsiniz. Tuist'i kullanmak için geçiş yapmak zorunda değilsiniz: [XcodeGen ile Tuist karşılaştırması](https://tuist.dev/compare/xcodegen), Xcode önbelleği ve derleme içgörüleri gibi hangi yeteneklerin bir XcodeGen projesiyle çalıştığını ve geçişin ne zaman worthwhile olduğunu açıklar.

> [!TIP]
> **YAML yerine Swift**
>
> Birçok kuruluş, yapılandırma formatı olarak Swift kullandığı için Tuist'i bir proje oluşturma aracı olarak da tercih eder. Swift, geliştiricilerin aşina olduğu bir programlama dilidir ve Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.


Aşağıda, projelerinizi XcodeGen'den Tuist'e taşımanıza yardımcı olacak bazı hususlar ve yönergeler yer almaktadır.

## Proje oluşturma {#project-generation}

Hem Tuist hem de XcodeGen, proje tanımınızı Xcode projelerine ve çalışma alanlarına dönüştüren bir `generate` komutu sağlar.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Fark, düzenleme deneyiminde yatmaktadır. Tuist ile, anında açabilir ve üzerinde çalışmaya başlayabileceğiniz bir Xcode projesi oluşturan `tuist edit` komutunu çalıştırabilirsiniz. Bu, projenizde hızlı değişiklikler yapmak istediğinizde özellikle kullanışlıdır.

## `project.yaml` {#projectyaml}

XcodeGen'in `project.yaml` tanım dosyası `Project.swift` haline gelir. Ayrıca, projelerin çalışma alanlarında nasıl gruplandırılacağını özelleştirmenin bir yolu olarak `Workspace.swift` dosyanız olabilir. Diğer projelerdeki hedeflere referans veren hedeflere sahip bir `Project.swift` projeniz de olabilir. Bu durumlarda, Tuist tüm projeleri içeren bir Xcode Çalışma Alanı oluşturur.

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

> [!TIP]
> **Xcode'un dili**
>
> Hem XcodeGen hem de Tuist, Xcode'un dilini ve kavramlarını benimser. Ancak, Tuist'in Swift tabanlı yapılandırması, Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.


## Şablonlar {#spec-templates}

Proje yapılandırması için bir dil olarak YAML'in dezavantajlarından biri, kutudan çıkar çıkmaz YAML dosyaları arasında yeniden kullanılabilirliği desteklememesidir. Bu, projeleri tanımlarken yaygın bir ihtiyaçtır ve XcodeGen bunu kendi özel çözümü olan *"şablonlar"* ile çözmek zorunda kalmıştır. Tuist'te yeniden kullanılabilirlik, dilin kendisine, yani Swift'e ve tüm manifest dosyalarınızda kodun yeniden kullanılmasına olanak tanıyan <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcılar</.localized_link> adlı bir Swift modülüne dahildir.

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
import ProjectDescriptionHelpers

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature"))
```
:::
