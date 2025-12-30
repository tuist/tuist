---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Bir XcodeGen projesini taşıma {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen), Xcode projelerini tanımlamak
için [bir yapılandırma
biçimi](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
olarak YAML kullanan bir proje oluşturma aracıdır. Birçok kuruluş **Xcode
projeleriyle çalışırken sık sık ortaya çıkan Git çakışmalarından kaçmak için bu
aracı benimsemiştir.** Ancak, sık Git çakışmaları kuruluşların yaşadığı birçok
sorundan sadece biridir. Xcode, geliştiricileri, projelerin geniş ölçekte
sürdürülmesini ve optimize edilmesini zorlaştıran çok sayıda karmaşıklık ve
örtük yapılandırma ile karşı karşıya bırakır. XcodeGen, bir proje yöneticisi
değil, Xcode projeleri üreten bir araç olduğu için tasarım gereği bu konuda
yetersiz kalıyor. Xcode projeleri üretmenin ötesinde size yardımcı olacak bir
araca ihtiyacınız varsa Tuist'i düşünebilirsiniz.

::: tip SWIFT OVER YAML
<!-- -->
Birçok kuruluş, yapılandırma biçimi olarak Swift'i kullandığı için Tuist'i proje
oluşturma aracı olarak da tercih ediyor. Swift, geliştiricilerin aşina olduğu
bir programlama dilidir ve onlara Xcode'un otomatik tamamlama, tür denetimi ve
doğrulama özelliklerini kullanma kolaylığı sağlar.
<!-- -->
:::

Aşağıda, projelerinizi XcodeGen'den Tuist'e taşımanıza yardımcı olacak bazı
hususlar ve yönergeler yer almaktadır.

## Proje üretimi {#project-generation}

Hem Tuist hem de XcodeGen, proje bildiriminizi Xcode projelerine ve çalışma
alanlarına dönüştüren bir `generate` komutu sağlar.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Aradaki fark düzenleme deneyiminde yatıyor. Tuist ile, açıp üzerinde çalışmaya
başlayabileceğiniz bir Xcode projesini anında oluşturan `tuist edit` komutunu
çalıştırabilirsiniz. Bu, özellikle projenizde hızlı değişiklikler yapmak
istediğinizde kullanışlıdır.

## `proje.yaml` {#projectyaml}

XcodeGen'in `project.yaml` açıklama dosyası `Project.swift` haline gelir.
Ayrıca, projelerin çalışma alanlarında nasıl gruplandırılacağını özelleştirmenin
bir yolu olarak `Workspace.swift` dosyasına sahip olabilirsiniz. Ayrıca, diğer
projelerdeki hedefleri referans alan hedeflere sahip bir projeniz
`Project.swift` olabilir. Bu durumlarda, Tuist tüm projeleri içeren bir Xcode
Çalışma Alanı oluşturacaktır.

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
Hem XcodeGen hem de Tuist, Xcode'un dilini ve kavramlarını benimser. Ancak
Tuist'in Swift tabanlı yapılandırması size Xcode'un otomatik tamamlama, tür
denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar.
<!-- -->
:::

## Özel şablonlar {#spec-templates}

Proje yapılandırması için bir dil olarak YAML'nin dezavantajlarından biri,
kutudan çıkan YAML dosyaları arasında yeniden kullanılabilirliği
desteklememesidir. Bu, XcodeGen'in *"templates"* adlı kendi özel çözümü ile
çözmek zorunda kaldığı projeleri tanımlarken yaygın bir ihtiyaçtır. Tuist'in
yeniden kullanılabilirliği, dilin kendisine, Swift'e ve tüm manifesto
dosyalarınızda kodun yeniden kullanılmasına olanak tanıyan
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</LocalizedLink> adlı bir Swift modülüne yerleştirilmiştir.

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
