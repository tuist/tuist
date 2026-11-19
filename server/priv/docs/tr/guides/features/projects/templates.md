---
{
  "title": "Şablonlar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizde kod oluşturmak için Tuist'te şablonların nasıl oluşturulacağını ve kullanılacağını öğrenin."
}
---
# Şablonlar {#templates}

Yerleşik bir mimariye sahip projelerde geliştiriciler, projeyle tutarlı yeni bileşenler veya özellikler başlatmak isteyebilir. `tuist scaffold` ile bir şablondan dosya üretebilirsiniz. Kendi şablonlarınızı tanımlayabilir veya Tuist ile birlikte gelenleri kullanabilirsiniz. İskele oluşturmanın faydalı olabileceği bazı senaryolar şunlardır:

- Belirli bir mimariyi takip eden yeni bir özellik oluşturun: `tuist scaffold viper --name MyFeature`.
- Yeni projeler oluşturun: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Görüş bildirmeyen**
>
> Tuist, şablonlarınızın içeriği ve bunları ne amaçla kullandığınız konusunda herhangi bir görüş belirtmez. Tek gereklilik, belirli bir dizinde bulunmalarıdır.


## Bir şablon tanımlama {#defining-a-template}

Şablonları tanımlamak için <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> komutunu çalıştırabilir ve ardından şablonunuzu temsil eden `name_of_template` adında bir dizini `Tuist/Templates` altında oluşturabilirsiniz. Şablonların, şablonu açıklayan `name_of_template.swift` adlı bir manifest dosyasına ihtiyacı vardır. Dolayısıyla, `framework` adında bir şablon oluşturuyorsanız, `Tuist/Templates` konumunda `framework` adında yeni bir dizin ve `framework.swift` adında bir manifest dosyası oluşturmalısınız; bu dosya şu şekilde görünebilir:


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

## Bir şablon kullanma {#using-a-template}

Şablonu tanımladıktan sonra, onu `scaffold` komutuyla kullanabiliriz:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Platform isteğe bağlı bir argüman olduğundan, komutu `--platform macos` argümanı olmadan da çağırabiliriz.


`.string` ve `.files` yeterli esneklik sağlamıyorsa, `.file` seçeneği aracılığıyla [Stencil](https://stencil.fuller.li/en/latest/) şablonlama dilinden yararlanabilirsiniz. Bunun yanı sıra, burada tanımlanan ek filtreleri de kullanabilirsiniz.

Dize enterpolasyonu kullanarak yukarıdaki `\(nameAttribute)` ifadesi `{{ name }}` olarak çözülür. Şablon tanımında Stencil filtrelerini kullanmak isterseniz, bu enterpolasyonu manuel olarak uygulayabilir ve istediğiniz filtreleri ekleyebilirsiniz. Örneğin, name özelliğinin küçük harfli değerini almak için `\(nameAttribute)` yerine `{ { name | lowercase } }` kullanabilirsiniz.

Tam klasörleri belirtilen bir yola kopyalama imkânı sunan `.directory` seçeneğini de kullanabilirsiniz.

> [!TIP]
> **Proje açıklama yardımcıları**
>
> Şablonlar, kodu şablonlar arasında yeniden kullanmak için <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</.localized_link> kullanımını destekler.
