---
{
  "title": "Bir XcodeGen projesini taşıma",
  "titleTemplate": ":title · Taşıma · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizi XcodeGen'den Tuist'e nasıl taşıyacağınızı öğrenin."
}
---
# XcodeGen projesini taşıma {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), Xcode projelerini tanımlamak için YAML'yi [yapılandırma biçimi](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) olarak kullanan bir proje oluşturma aracıdır. Birçok kuruluş, **Xcode projeleriyle çalışırken sıkça ortaya çıkan Git çakışmalarından kurtulmak amacıyla bu aracı benimsedi.** Ancak sık Git çakışmaları, kuruluşların karşılaştığı birçok sorundan yalnızca biridir. Xcode, geliştiricilere projeleri büyük ölçekte sürdürmeyi ve optimize etmeyi zorlaştıran çok sayıda karmaşıklık ve örtük yapılandırma sunar. XcodeGen, Xcode projeleri üreten bir araç olduğu ve bir proje yöneticisi olmadığı için tasarım gereği bu alanda yetersiz kalır. Xcode projeleri oluşturmanın ötesinde size yardımcı olacak bir araca ihtiyacınız varsa, Tuist'i değerlendirmek isteyebilirsiniz.

> [!TIP]
> **YAML yerine Swift**
>
> Birçok kuruluş, yapılandırma biçimi olarak Swift kullandığı için proje oluşturma aracı olarak da Tuist'i tercih eder. Swift, geliştiricilerin aşina olduğu bir programlama dilidir ve Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.


Aşağıda, projelerinizi XcodeGen'den Tuist'e taşırken dikkate almanız gereken hususlar ve yönergeler yer almaktadır.

## Proje oluşturma {#project-generation}

Hem Tuist hem de XcodeGen, proje tanımınızı Xcode projelerine ve çalışma alanlarına dönüştüren bir `generate` komutu sunar.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Fark, düzenleme deneyiminde yatmaktadır. Tuist ile, anında açılıp üzerinde çalışmaya başlayabileceğiniz bir Xcode projesi oluşturan `tuist edit` komutunu çalıştırabilirsiniz. Bu, projenizde hızlı değişiklikler yapmak istediğinizde özellikle kullanışlıdır.

## `project.yaml` {#projectyaml}

XcodeGen'in `project.yaml` tanım dosyası `Project.swift` haline gelir. Ayrıca, projelerin çalışma alanlarında nasıl gruplandırılacağını özelleştirmek için `Workspace.swift` dosyasını kullanabilirsiniz. Diğer projelerdeki hedeflere başvuran hedeflere sahip bir `Project.swift` projesi de oluşturabilirsiniz. Bu durumlarda Tuist, tüm projeleri içeren bir Xcode Çalışma Alanı oluşturur.

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
> Hem XcodeGen hem de Tuist, Xcode'un dilini ve kavramlarını benimser. Ancak Tuist'in Swift tabanlı yapılandırması, Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.


## Şablonlar {#spec-templates}

Proje yapılandırması için bir dil olarak YAML'nin dezavantajlarından biri, YAML dosyaları arasında yeniden kullanılabilirliği kutudan çıkar çıkmaz desteklememesidir. Bu, projeleri tanımlarken sıkça karşılaşılan bir ihtiyaçtır ve XcodeGen bunu *"şablonlar"* adlı kendi özel çözümüyle çözmek zorunda kalmıştır. Tuist'te yeniden kullanılabilirlik, dilin kendisine, yani Swift'e ve tüm bildirim dosyalarınız arasında kodun yeniden kullanılmasını sağlayan <.localized_link href="/guides/features/projects/code-sharing">proje tanımı yardımcıları</.localized_link> adlı bir Swift modülüne dahildir.

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
