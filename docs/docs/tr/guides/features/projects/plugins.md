---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Eklentiler {#plugins}

Eklentiler, Tuist eserlerini birden fazla proje arasında paylaşmak ve yeniden
kullanmak için bir araçtır. Aşağıdaki eserler desteklenmektedir:

- <LocalizedLink href="/guides/features/projects/code-sharing">Birden fazla projede proje açıklama yardımcıları</LocalizedLink>.
- <LocalizedLink href="/guides/features/projects/templates">Birden fazla projedeki şablonlar</LocalizedLink>.
- Birden fazla projedeki görevler.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Birden fazla projede kaynak erişimcisi</LocalizedLink> şablonu

Eklentilerin Tuist'in işlevselliğini genişletmek için basit bir yol olarak
tasarlandığını unutmayın. Bu nedenle **dikkate alınması gereken bazı
sınırlamalar vardır**:

- Bir eklenti başka bir eklentiye bağımlı olamaz.
- Bir eklenti üçüncü taraf Swift paketlerine bağımlı olamaz
- Bir eklenti, eklentiyi kullanan projedeki proje açıklama yardımcılarını
  kullanamaz.

Daha fazla esnekliğe ihtiyacınız varsa, araç için bir özellik önermeyi veya
Tuist'in üretim çerçevesi üzerine kendi çözümünüzü oluşturmayı düşünün,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Eklenti türleri {#plugin-types}

### Proje açıklaması yardımcı eklentisi {#project-description-helper-plugin}

Bir proje açıklama yardımcı eklentisi, eklentinin adını bildiren bir
`Plugin.swift` manifest dosyası ve yardımcı Swift dosyalarını içeren bir
`ProjectDescriptionHelpers` dizini içeren bir dizin ile temsil edilir.

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

### Kaynak erişimci şablonları eklentisi {#resource-accessor-templates-plugin}

sentezlenmiş kaynak erişimcilerini paylaşmanız gerekiyorsa bu
tür bir eklenti kullanabilirsiniz. Eklenti, eklentinin adını bildiren bir
`Plugin.swift` manifest dosyası ve kaynak erişimcisi şablon dosyalarını içeren
bir `ResourceSynthesizers` dizini içeren bir dizin ile temsil edilir.


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
case](https://en.wikipedia.org/wiki/Camel_case) sürümüdür:

| Kaynak türü       | Şablon dosya adı         |
| ----------------- | ------------------------ |
| Dizeler           | Dizeler.şablon           |
| Varlıklar         | Assets.stencil           |
| Emlak Listeleri   | Plists.stencil           |
| Yazı Tipleri      | Fonts.stencil            |
| Çekirdek Veri     | CoreData.stencil         |
| Arayüz Oluşturucu | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

Projedeki kaynak sentezleyicileri tanımlarken, eklentideki şablonları kullanmak
için eklenti adını belirtebilirsiniz:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Görev eklentisi <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Görev eklentileri kullanımdan kaldırılmıştır. Projeniz için bir otomasyon çözümü
arıyorsanız [bu blog
yazısına](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) göz
atın.
<!-- -->
:::

Görevler, `tuist-` adlandırma kuralına uymaları halinde `tuist` komutu
aracılığıyla çağrılabilen `$PATH`-açık yürütülebilir dosyalarıdır. Önceki
sürümlerde Tuist, `tuist plugin` altında `build`, `run`, `test` ve `archive`
görevleri için Swift paketi içindeki yürütülebilir dosyalar tarafından temsil
edilen bazı zayıf kurallar ve araçlar sağladı, ancak aracın bakım yükünü ve
karmaşıklığını artırdığı için bu özelliği kullanımdan kaldırdık.

Görevleri dağıtmak için Tuist kullanıyorsanız
- Mantığınızdan proje grafiğine erişmek için her Tuist sürümü ile dağıtılan
  `ProjectAutomation.xcframework` kullanmaya devam edebilirsiniz `let graph =
  try Tuist.graph()`. Komut, `tuist` komutunu çalıştırmak ve proje grafiğinin
  bellek içi gösterimini döndürmek için sistem sürecini kullanır.
- Görevleri dağıtmak için, GitHub sürümlerine `arm64` ve `x86_64` destekleyen
  bir yağ ikilisi eklemenizi ve bir yükleme aracı olarak
  [Mise](https://mise.jdx.dev) kullanmanızı öneririz. Mise'e aracınızı nasıl
  yükleyeceği konusunda talimat vermek için bir eklenti deposuna ihtiyacınız
  olacaktır. Referans olarak
  [Tuist's](https://github.com/asdf-community/asdf-tuist) kullanabilirsiniz.
- Aracınızı `tuist-{xxx}` olarak adlandırırsanız ve kullanıcılar `mise install`
  çalıştırarak yükleyebilirlerse, doğrudan çağırarak ya da `tuist xxx`
  aracılığıyla çalıştırabilirler.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`ProjectAutomation` ve `XcodeGraph` modellerini, proje grafiğinin tamamını
kullanıcıya sunan geriye dönük uyumlu tek bir çerçevede birleştirmeyi
planlıyoruz. Dahası, oluşturma mantığını kendi CLI'nizden de kullanabileceğiniz
yeni bir katmana, `XcodeGraph` çıkaracağız. Bunu kendi Tuist'inizi oluşturmak
gibi düşünün.
<!-- -->
:::

## Eklentileri kullanma {#using-plugins}

Bir eklentiyi kullanmak için projenizin
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

Bir eklentiyi farklı depolarda bulunan projeler arasında yeniden kullanmak
istiyorsanız, eklentinizi bir Git deposuna gönderebilir ve `Tuist.swift`
dosyasında referans gösterebilirsiniz:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Eklentileri ekledikten sonra, `tuist install` eklentileri global bir önbellek
dizinine getirecektir.

::: info NO VERSION RESOLUTION
<!-- -->
Sizin de fark etmiş olabileceğiniz gibi, eklentiler için sürüm çözünürlüğü
sağlamıyoruz. Tekrarlanabilirliği sağlamak için Git etiketlerini veya SHA'ları
kullanmanızı öneririz.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
Bir proje açıklama yardımcıları eklentisi kullanılırken, yardımcıları içeren
modülün adı eklentinin adıdır
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
