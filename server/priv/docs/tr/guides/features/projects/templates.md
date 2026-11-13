---
{
  "title": "Şablonlar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizde kod oluşturmak için Tuist'te şablonların nasıl oluşturulup kullanılacağını öğrenin."
}
---
# Şablonlar {#templates}

Yerleşik bir mimariye sahip projelerde, geliştiriciler projeyle tutarlı yeni bileşenler veya özellikler başlatmak isteyebilir. `tuist scaffold` ile bir şablondan dosyalar oluşturabilirsiniz. Kendi şablonlarınızı tanımlayabilir veya Tuist ile birlikte gelen şablonları kullanabilirsiniz. İskele oluşturmanın yararlı olabileceği bazı senaryolar şunlardır:

- Belirli bir mimariyi takip eden yeni bir özellik oluşturun: `tuist scaffold viper --name MyFeature`.
- Yeni projeler oluşturun: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Tarayışsız**
>
> Tuist, şablonlarınızın içeriği ve bunları ne amaçla kullandığınız konusunda herhangi bir dayatmada bulunmaz. Tek gereksinim, belirli bir dizinde bulunmalarıdır.


## Şablon tanımlama {#defining-a-template}

Şablonları tanımlamak için <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> komutunu çalıştırabilir ve ardından şablonunuzu temsil eden `name_of_template` adında bir dizini `Tuist/Templates` altında oluşturabilirsiniz. Şablonların, şablonu açıklayan bir bildirim dosyasına, yani `name_of_template.swift` dosyasına ihtiyacı vardır. Dolayısıyla, `framework` adında bir şablon oluşturuyorsanız, `Tuist/Templates` konumunda `framework` adında yeni bir dizin ve içinde `framework.swift` adında bir bildirim dosyası oluşturmalısınız; bu dosya şu şekilde görünebilir:


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

Şablonu tanımladıktan sonra, onu `scaffold` komutuyla kullanabiliriz:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> platform isteğe bağlı bir bağımsız değişken olduğundan, komutu `--platform macos` bağımsız değişkeni olmadan da çağırabiliriz.


Eğer `.string` ve `.files` yeterli esneklik sağlamıyorsa, `.file` durumu aracılığıyla [Stencil](https://stencil.fuller.li/en/latest/) şablonlama dilinden yararlanabilirsiniz. Bunun yanı sıra, burada tanımlanan ek filtreleri de kullanabilirsiniz.

Dize enterpolasyonu kullanarak, yukarıdaki `\(nameAttribute)` ifadesi `{{ name }}` olarak çözümlenir. Şablon tanımında Stencil filtrelerini kullanmak isterseniz, bu enterpolasyonu manuel olarak uygulayabilir ve istediğiniz filtreleri ekleyebilirsiniz. Örneğin, name özelliğinin küçük harfli değerini almak için `\(nameAttribute)` yerine `{ { name | lowercase } }` kullanabilirsiniz.

Ayrıca, tüm klasörleri belirtilen bir yola kopyalama olanağı sağlayan `.directory` öğesini de kullanabilirsiniz.

> [!TIP]
> **Proje açıklama yardımcıları**
>
> Şablonlar, kodu şablonlar arasında yeniden kullanmak için <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</.localized_link> kullanımını destekler.
