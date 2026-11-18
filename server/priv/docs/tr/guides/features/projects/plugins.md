---
{
  "title": "Eklentiler",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'te işlevselliği genişletmek için eklentilerin nasıl oluşturulacağını ve kullanılacağını öğrenin."
}
---
# Eklentiler {#plugins}

Eklentiler, Tuist yapıtlarını birden fazla projede paylaşmak ve yeniden kullanmak için bir araçtır. Aşağıdaki yapıtlar desteklenir:

- Birden fazla projede <.localized_link href="/guides/features/projects/code-sharing">Proje tanımı yardımcıları</.localized_link>.
- Birden fazla projede <.localized_link href="/guides/features/projects/templates">Şablonlar</.localized_link>.
- Birden fazla projede görevler.
- Birden fazla projede <.localized_link href="/guides/features/projects/synthesized-files">Kaynak erişimcisi</.localized_link> şablonu

Eklentilerin Tuist işlevselliğini genişletmenin basit bir yolu olarak tasarlandığını unutmayın. Bu nedenle dikkate alınması gereken **bazı sınırlamalar** vardır:

- Bir eklenti başka bir eklentiye bağımlı olamaz.
- Bir eklenti üçüncü taraf Swift paketlerine bağımlı olamaz.
- Bir eklenti, eklentiyi kullanan projedeki proje tanımı yardımcılarını kullanamaz.

Daha fazla esnekliğe ihtiyacınız varsa, araç için bir özellik önermeyi veya Tuist’in oluşturma çerçevesi üzerine kendi çözümünüzü geliştirmeyi düşünün: [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator).

## Eklenti türleri {#plugin-types}

### Proje tanımı yardımcı eklentisi {#project-description-helper-plugin}

Bir proje tanımı yardımcı eklentisi, eklentinin adını bildiren bir `Plugin.swift` bildirim dosyası ve yardımcı Swift dosyalarını içeren bir `ProjectDescriptionHelpers` dizini barındıran bir dizinle temsil edilir.

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

<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">Sentezlenmiş kaynak erişimcilerini</.localized_link> paylaşmanız gerekiyorsa bu tür bir eklentiyi kullanabilirsiniz. Eklenti, eklentinin adını bildiren bir `Plugin.swift` bildirim dosyası ve kaynak erişimci şablon dosyalarını içeren bir `ResourceSynthesizers` dizini barındıran bir dizinle temsil edilir.


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

Şablonun adı, kaynak türünün [camelCase](https://en.wikipedia.org/wiki/Camel_case) sürümüdür:

| Kaynak türü | Şablon dosya adı |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

Projedeki kaynak sentezleyicileri tanımlarken, eklentiden gelen şablonları kullanmak üzere eklenti adını belirtebilirsiniz:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Görev eklentisi <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **Kullanımdan kaldırıldı**
>
> Görev eklentileri kullanımdan kaldırıldı. Projeniz için bir otomasyon çözümü arıyorsanız [bu blog yazısına](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects) göz atın.


Görevler, `tuist-<task-name>` adlandırma kuralına uyduklarında `tuist` komutu aracılığıyla çağrılabilen `$PATH` ile erişilebilen çalıştırılabilir dosyalardır. Daha önceki sürümlerde Tuist, Swift Paketlerindeki çalıştırılabilir dosyalarla temsil edilen `build`, `run`, `test` ve `archive` görevleri için `tuist plugin` altında bazı zayıf kurallar ve araçlar sağlıyordu; ancak bu özellik aracın bakım yükünü ve karmaşıklığını artırdığı için kullanımdan kaldırdık.

Görevleri eklenti olarak dağıtıyorsanız, bunları bunun yerine bağımsız çalıştırılabilir dosyalar olarak oluşturun:

- Mantığınızdan proje grafiğine `let graph = try Tuist.graph()` ile erişmek için her Tuist sürümüyle birlikte dağıtılan `ProjectAutomation.xcframework` kullanmaya devam edebilirsiniz. Bu, `tuist` öğesini bir alt süreç olarak çalıştırır ve proje grafiğinin bellek içi temsilini döndürür.
- Görevleri dağıtmak için GitHub sürümlerinde `arm64` ve `x86_64` destekleyen evrensel bir ikili yayınlamanızı ve kurulum aracı olarak [Mise](https://mise.jdx.dev) kullanmanızı öneririz. Mise’e aracınızı nasıl kuracağını belirtmek için bir eklenti deposuna ihtiyacınız olacak. Referans olarak [Tuist’in](https://github.com/asdf-community/asdf-tuist) deposunu kullanabilirsiniz.
- Aracınıza `tuist-{xxx}` adını verirseniz ve kullanıcılar `mise install` komutunu çalıştırarak onu kurabilirse, aracı doğrudan çağırarak veya `tuist xxx` üzerinden çalıştırabilirler.

> [!NOTE]
> **ProjectAutomation’ın geleceği**
>
> `ProjectAutomation` ve `XcodeGraph` modellerini, proje grafiğinin tamamını kullanıcıya açan tek bir geriye dönük uyumlu çerçevede birleştirmeyi planlıyoruz. Ayrıca oluşturma mantığını, kendi CLI’nızdan da kullanabileceğiniz yeni bir katman olan `XcodeGraph` içine çıkaracağız. Bunu kendi Tuist’inizi oluşturmak olarak düşünebilirsiniz.


## Eklentileri kullanma {#using-plugins}

Bir eklentiyi kullanmak için onu projenizin [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) bildirim dosyasına eklemeniz gerekir:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Bir eklentiyi farklı depolarda bulunan projeler arasında yeniden kullanmak istiyorsanız, eklentinizi bir Git deposuna gönderebilir ve `Tuist.swift` dosyasında buna başvurabilirsiniz:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Eklentileri ekledikten sonra `tuist install` eklentileri genel bir önbellek dizininden alacaktır.

> [!NOTE]
> **Sürüm çözümlemesi yok**
>
> Fark etmiş olabileceğiniz gibi, eklentiler için sürüm çözümlemesi sağlamıyoruz. Tekrarlanabilirliği sağlamak için Git etiketlerini veya SHA değerlerini kullanmanızı öneririz.


> [!TIP]
> **Proje tanımı yardımcıları eklentileri**
>
> Bir proje tanımı yardımcıları eklentisi kullanırken, yardımcıları içeren modülün adı eklentinin adıdır
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
