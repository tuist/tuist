---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Şablonlar {#templates}

Yerleşik bir mimariye sahip projelerde, geliştiriciler projeyle tutarlı yeni
bileşenler veya özellikler başlatmak isteyebilir. `tuist scaffold` ile şablondan
dosyalar oluşturabilirsiniz. Kendi şablonlarınızı tanımlayabilir veya Tuist ile
birlikte sunulan şablonları kullanabilirsiniz. Scaffolding'in yararlı
olabileceği bazı senaryolar şunlardır:

- Verilen mimariyi takip eden yeni bir özellik oluşturun: `tuist scaffold viper
  --name MyFeature`.
- Yeni projeler oluşturun: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist, şablonlarınızın içeriği ve bunları ne amaçla kullandığınız konusunda bir
görüş belirtmez. Şablonların yalnızca belirli bir dizinde bulunması gerekir.
<!-- -->
:::

## Şablon tanımlama {#defining-a-template}

Şablonları tanımlamak için
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> komutunu çalıştırıp, şablonunuzu temsil eden
`name_of_template` adlı bir dizin oluşturun. `Tuist/Templates` Şablonlar,
şablonu açıklayan bir manifest dosyasına ihtiyaç duyar:
`name_of_template.swift`. Dolayısıyla, `framework` adlı bir şablon
oluşturuyorsanız, `Tuist/Templates` altında `framework` adlı yeni bir dizin
oluşturmalı ve `framework.swift` adlı bir manifest dosyası eklemelisiniz. Bu
dosya şöyle görünebilir:


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

Şablonu tanımladıktan sonra, `scaffold` komutundan kullanabiliriz:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
Platform isteğe bağlı bir argüman olduğundan, komutu `--platform macos` argümanı
olmadan da çağırabiliriz.
<!-- -->
:::

`.string` ve `.files` yeterli esneklik sağlamıyorsa, `.file` örneğinde olduğu
gibi [Stencil](https://stencil.fuller.li/en/latest/) şablon dilini
kullanabilirsiniz. Bunun yanı sıra, burada tanımlanan ek filtreleri de
kullanabilirsiniz.

`Dize enterpolasyonu kullanarak, `\(nameAttribute)` yukarıdaki ifade `{{ name
}}` şeklinde çözülür. Şablon tanımında Stencil filtreleri kullanmak isterseniz,
bu enterpolasyonu manuel olarak kullanabilir ve istediğiniz filtreleri
ekleyebilirsiniz. Örneğin, \(nameAttribute)` yerine `{ { name | lowercase } }`
kullanarak name özniteliğinin küçük harfli değerini elde edebilirsiniz.

Ayrıca, `.directory` adresini kullanarak tüm klasörleri belirli bir yola
kopyalayabilirsiniz.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Şablonlar, şablonlar arasında kodu yeniden kullanmak için
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklaması
yardımcıları</LocalizedLink> kullanımını destekler.
<!-- -->
:::
