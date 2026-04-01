---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Eklentiler {#plugins}

Eklentiler, Tuist öğelerini birden fazla proje arasında paylaşmak ve yeniden
kullanmak için bir araçtır. Aşağıdaki öğeler desteklenmektedir:

- <LocalizedLink href="/guides/features/projects/code-sharing">Birden fazla
  projeye yayılan proje açıklaması yardımcıları</LocalizedLink>.
- <LocalizedLink href="/guides/features/projects/templates">Birden fazla projede
  kullanılan şablonlar</LocalizedLink>.
- Birden fazla projeye yayılan görevler.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Birden fazla
  projede kullanılan kaynak erişimci</LocalizedLink> şablonu

Eklentiler, Tuist'in işlevselliğini genişletmenin basit bir yolu olarak
tasarlanmıştır. Bu nedenle, dikkate alınması gereken bazı sınırlamalar vardır
**** :

- Bir eklenti, başka bir eklentiye bağımlı olamaz.
- Bir eklenti, üçüncü taraf Swift package'lerine bağımlı olamaz
- Bir eklenti, kendisini kullanan projenin proje açıklaması yardımcılarını
  kullanamaz.

Daha fazla esnekliğe ihtiyacınız varsa, araç için bir özellik önermeyi veya
Tuist'in oluşturma çerçevesini kullanarak kendi çözümünüzü geliştirmeyi düşünün,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Eklenti türleri {#plugin-types}

### Proje açıklaması yardımcı eklentisi {#project-description-helper-plugin}

Bir proje açıklaması yardımcı eklentisi, eklentinin adını bildiren bir
`Plugin.swift` manifest dosyası ve yardımcı Swift dosyalarını içeren bir
`ProjectDescriptionHelpers` dizini içeren bir dizinle temsil edilir.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### Kaynak erişim şablonları eklentisi {#resource-accessor-templates-plugin}

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">sentezlenmiş
kaynak erişimcileri</LocalizedLink> paylaşmanız gerekiyorsa, bu tür bir
eklentiyi kullanabilirsiniz. Eklenti, eklentinin adını bildiren bir
`Plugin.swift` manifest dosyası ve kaynak erişimci şablon dosyalarını içeren bir
`ResourceSynthesizers` dizini içeren bir dizinle temsil edilir.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

Şablonun adı, kaynak türünün [camel
case](https://en.wikipedia.org/wiki/Camel_case) versiyonudur:

| Kaynak türü       | Şablon dosya adı         |
| ----------------- | ------------------------ |
| Diziler           | Strings.stencil          |
| Varlıklar         | Assets.stencil           |
| Özellik Listeleri | Plists.stencil           |
| Yazı tipleri      | Fonts.stencil            |
| Temel Veriler     | CoreData.stencil         |
| Arayüz Oluşturucu | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

Projede kaynak sentezleyicileri tanımlarken, eklentideki şablonları kullanmak
için eklenti adını belirtebilirsiniz:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Görev eklentisi <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Görev eklentileri artık kullanılmamaktadır. Projeniz için bir otomasyon çözümü
arıyorsanız [bu blog
yazısını](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)
inceleyin.
<!-- -->
:::

`` Görevler, `$PATH` adresinde bulunan ve` komutu aracılığıyla çağrılabilen
yürütülebilir dosyalardır; ancak bunun için `tuist-<task-name>` adlandırma
kuralına uymaları gerekir. Önceki sürümlerde Tuist, `tuist plugin` altında,
Swift Packagelerindeki yürütülebilir dosyalarla temsil edilen `build , `run`,
`test` ve `archive` görevlerini oluşturmak için bazı zayıf kurallar ve araçlar
sağlıyordu; ancak bu özellik, bakım yükünü ve aracın karmaşıklığını artırdığı
için artık kullanılmamaktadır.</task-name>

Görevleri dağıtmak için Tuist kullanıyorsanız,
- Her Tuist sürümüyle birlikte dağıtılan `ProjectAutomation.xcframework`
  dosyasını kullanmaya devam ederek, `let graph = try Tuist.graph()` komutuyla
  mantığınızdan proje grafiğine erişebilirsiniz. Bu komut, sistem sürecini
  kullanarak `tuist` komutunu çalıştırır ve proje grafiğinin bellek içi
  temsilini döndürür.
- Görevleri dağıtmak için, GitHub sürümlerine `arm64` ve `x86_64` adreslerini
  destekleyen bir fat binary eklemenizi ve kurulum aracı olarak
  [Mise](https://mise.jdx.dev) kullanmanızı öneririz. Mise'ye aracınızı nasıl
  kuracağını öğretmek için bir eklenti deposuna ihtiyacınız olacak. Referans
  olarak [Tuist'in](https://github.com/asdf-community/asdf-tuist) deposunu
  kullanabilirsiniz.
- Aracınıza `tuist-{xxx}` adını verirseniz ve kullanıcılar `mise install`
  komutunu çalıştırarak yükleyebilirse, aracı doğrudan çağırarak veya `tuist
  xxx` komutunu kullanarak çalıştırabilirler.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`, ProjectAutomation` ve `XcodeGraph` modellerini, proje grafiğinin tamamını
kullanıcıya sunan tek bir geriye dönük uyumlu çerçeve altında birleştirmeyi
planlıyoruz. Ayrıca, oluşturma mantığını yeni bir katmana, `XcodeGraph`
ayıracağız; bu katmanı kendi CLI'nizden de kullanabilirsiniz. Bunu kendi
Tuist'inizi oluşturmak olarak düşünün.
<!-- -->
:::

## Eklentileri kullanma {#using-plugins}

Bir eklentiyi kullanmak için, onu projenizin
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
manifest dosyasına eklemeniz gerekir:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Farklı depolarda bulunan projeler arasında bir eklentiyi yeniden kullanmak
istiyorsanız, eklentinizi bir Git deposuna yükleyebilir ve `Tuist.swift`
dosyasında ona referans verebilirsiniz:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Eklentileri ekledikten sonra, `tuist install` komutu eklentileri genel önbellek
dizinine yükleyecektir.

::: info NO VERSION RESOLUTION
<!-- -->
Fark etmiş olabileceğiniz gibi, eklentiler için sürüm çözümleme hizmeti
sunmuyoruz. Tekrarlanabilirliği sağlamak için Git etiketleri veya SHA'ları
kullanmanızı öneririz.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
Bir proje açıklaması yardımcıları eklentisi kullanırken, yardımcıları içeren
modülün adı eklentinin adıdır
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
