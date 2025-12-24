---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Şablonlar {#templates}

Yerleşik bir mimariye sahip projelerde, geliştiriciler proje ile tutarlı yeni
bileşenleri veya özellikleri önyüklemek isteyebilir. ` tuist scaffold` ile bir
şablondan dosya oluşturabilirsiniz. Kendi şablonlarınızı tanımlayabilir veya
Tuist ile satılanları kullanabilirsiniz. Bunlar, iskelenin yararlı olabileceği
bazı senaryolardır:

- Belirli bir mimariyi izleyen yeni bir özellik oluşturun: `tuist scaffold viper
  --name MyFeature`.
- Yeni projeler oluşturun: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist, şablonlarınızın içeriği ve bunları ne için kullandığınız konusunda fikir
sahibi değildir. Sadece belirli bir dizinde olmaları gerekmektedir.
<!-- -->
:::

## Bir şablon tanımlama {#defining-a-template}

Şablonları tanımlamak için,
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> çalıştırabilir ve ardından şablonunuzu temsil eden
`Tuist/Templates` altında `name_of_template` adlı bir dizin oluşturabilirsiniz.
Şablonlar, şablonu tanımlayan `name_of_template.swift` adında bir manifesto
dosyasına ihtiyaç duyar. Dolayısıyla, `framework` adında bir şablon
oluşturuyorsanız, `Tuist/Templates` adresinde `framework` adında yeni bir dizin
oluşturmalı ve `framework.swift` adında aşağıdaki gibi görünebilecek bir
bildirim dosyası oluşturmalısınız:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## Şablon kullanma {#using-a-template}

Şablonu tanımladıktan sonra `scaffold` komutundan kullanabiliriz:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
Platform isteğe bağlı bir argüman olduğundan, komutu `--platform macos` argümanı
olmadan da çağırabiliriz.
<!-- -->
:::

`.string` ve `.files` yeterince esneklik sağlamıyorsa, `.file` durumu
aracılığıyla [Stencil](https://stencil.fuller.li/en/latest/) şablonlama dilinden
yararlanabilirsiniz. Bunun yanı sıra, burada tanımlanan ek filtreleri de
kullanabilirsiniz.

Dize enterpolasyonu kullanıldığında, `\(nameAttribute)` yukarıdaki `{{ name }}`
şeklinde çözümlenir. Şablon tanımında Stencil filtrelerini kullanmak isterseniz,
bu enterpolasyonu manuel olarak kullanabilir ve istediğiniz filtreleri
ekleyebilirsiniz. Örneğin, `{ { isim | küçük harf } }` yerine `\(nameAttribute)`
name niteliğinin küçük harfli değerini almak için.

Ayrıca, tüm klasörleri belirli bir yola kopyalama imkanı veren `.directory`
adresini de kullanabilirsiniz.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Şablonlar, kodun şablonlar arasında yeniden kullanılması için
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklama yardımcılarının</LocalizedLink> kullanımını destekler.
<!-- -->
:::
