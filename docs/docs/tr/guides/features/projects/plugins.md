---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Eklentiler {#plugins}

Eklentiler, Tuist artefaktlarını birden fazla projede paylaşmak ve yeniden
kullanmak için bir araçtır. Aşağıdaki artefaktlar desteklenmektedir:

- <LocalizedLink href="/guides/features/projects/code-sharing">Proje açıklaması
  yardımcıları</LocalizedLink> birden fazla projede.
- <LocalizedLink href="/guides/features/projects/templates">Birden fazla projede
  şablonlar</LocalizedLink>.
- Birden fazla projeye yayılan görevler.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Birden fazla
  projede kaynak erişimci</LocalizedLink> şablonu

Eklentiler, Tuist'in işlevselliğini basit bir şekilde genişletmek için
tasarlanmıştır. Bu nedenle, **dikkate alınması gereken bazı sınırlamalar
vardır**:

- Bir eklenti başka bir eklentiye bağımlı olamaz.
- Bir eklenti, üçüncü taraf Swift paketlerine bağlı olamaz.
- Bir eklenti, eklentiyi kullanan projedeki proje açıklaması yardımcılarını
  kullanamaz.

Daha fazla esnekliğe ihtiyacınız varsa, araç için bir özellik önermeyi veya
Tuist'in oluşturma çerçevesini temel alarak kendi çözümünüzü geliştirmeyi
düşünün,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Eklenti türleri {#plugin-types}

### Proje açıklaması yardımcı eklentisi {#project-description-helper-plugin}

Proje açıklaması yardımcı eklentisi, eklentinin adını bildiren bir
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
kaynak erişimcileri</LocalizedLink> paylaşmanız gerekiyorsa, bu tür bir eklenti
kullanabilirsiniz. Eklenti, eklentinin adını bildiren bir `Plugin.swift`
manifest dosyası ve kaynak erişimci şablon dosyalarını içeren bir
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

Görevler, `$PATH`-exposed çalıştırılabilir dosyalardır ve `tuist` komutu ile
çağrılabilirler, ancak `tuist-<task-name>` adlandırma kuralına uymaları gerekir.
Önceki sürümlerde, Tuist `tuist plugin` altında `build`, `run`, `test` ve
`archive` görevlerini temsil eden çalıştırılabilir dosyalar için bazı zayıf
kurallar ve araçlar sağlıyordu, ancak bu özelliği, aracın bakım yükünü ve
karmaşıklığını artırdığı için kullanımdan kaldırdık.</task-name>

Görevleri dağıtmak için Tuist kullanıyorsanız,
- Her Tuist sürümüyle birlikte dağıtılan `ProjectAutomation.xcframework`
  dosyasını kullanmaya devam ederek, mantığınızda `let graph = try
  Tuist.graph()` ile proje grafiğine erişebilirsiniz. Komut, `tuist` komutunu
  çalıştırmak için sistem sürecini kullanır ve proje grafiğinin bellekteki
  temsilini döndürür.
- Görevleri dağıtmak için, GitHub sürümlerinde `arm64` ve `x86_64` destekleyen
  bir fat binary eklemenizi ve [Mise](https://mise.jdx.dev) kurulum aracını
  kullanmanızı öneririz. Mise'ye aracınızı nasıl kuracağını öğretmek için bir
  eklenti deposuna ihtiyacınız olacak. Referans olarak
  [Tuist's](https://github.com/asdf-community/asdf-tuist) kullanabilirsiniz.
- Aracınızı `tuist-{xxx}` olarak adlandırırsanız ve kullanıcılar `mise install`
  komutunu çalıştırarak yükleyebilirse, aracı doğrudan çağırarak veya `tuist
  xxx` komutunu kullanarak çalıştırabilirler.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`ProjectAutomation` ve `XcodeGraph` modellerini, proje grafiğinin tamamını
kullanıcıya gösteren tek bir geriye dönük uyumlu çerçeveye birleştirmek
planlıyoruz. Ayrıca, oluşturma mantığını kendi CLI'nizden de kullanabileceğiniz
yeni bir katmana, `XcodeGraph` çıkaracağız. Bunu kendi Tuist'inizi oluşturmak
olarak düşünün.
<!-- -->
:::

## Eklentileri kullanma {#using-plugins}

Eklentiyi kullanmak için, onu projenizin
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

Farklı depolarda bulunan projelerde bir eklentiyi yeniden kullanmak
istiyorsanız, eklentinizi bir Git deposuna aktarabilir ve `Tuist.swift`
dosyasında ona başvurabilirsiniz:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Eklentileri ekledikten sonra, `tuist install` komutu eklentileri global bir
önbellek dizinine indirir.

::: info NO VERSION RESOLUTION
<!-- -->
Belki fark etmişsinizdir, eklentiler için sürüm çözünürlüğü sağlamıyoruz.
Tekrarlanabilirliği sağlamak için Git etiketleri veya SHA'lar kullanmanızı
öneririz.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
Proje açıklaması yardımcıları eklentisini kullanırken, yardımcıları içeren
modülün adı eklentinin adıdır.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
