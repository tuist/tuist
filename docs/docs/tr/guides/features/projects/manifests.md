---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifestolar {#manifests}

Tuist, projeleri ve çalışma alanlarını tanımlamak ve oluşturma sürecini
yapılandırmak için varsayılan olarak Swift dosyalarını kullanır. Bu dosyalar,
belgelerde **manifest files** olarak adlandırılır.

Swift'i kullanma kararı, paketleri tanımlamak için Swift dosyalarını kullanan
[Swift Package Manager](https://www.swift.org/documentation/package-manager/)
tarafından ilham alınarak verilmiştir. Swift'i kullanarak, derleyiciyi içeriğin
doğruluğunu onaylamak ve farklı manifest dosyalarında kodu yeniden kullanmak
için kullanabiliriz. Ayrıca, Xcode'un sözdizimi vurgulaması, otomatik tamamlama
ve doğrulama özellikleri sayesinde birinci sınıf bir düzenleme deneyimi
sunabiliriz.

::: info CACHING
<!-- -->
Manifest dosyaları derlenmesi gereken Swift dosyaları olduğundan, Tuist derleme
sonuçlarını önbelleğe alarak ayrıştırma sürecini hızlandırır. Bu nedenle,
Tuist'i ilk kez çalıştırdığınızda projenin oluşturulması biraz daha uzun
sürebilir. Sonraki çalıştırmalarda daha hızlı olacaktır.
<!-- -->
:::

## Project.swift {#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
manifest, bir Xcode projesini bildirir. Proje, manifest dosyasının bulunduğu
dizinde, `name` özelliğinde belirtilen adla oluşturulur.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
Manifesto kökünde bulunması gereken tek değişken `let project =
Project(...)`'dir. Manifestonun çeşitli bölümlerinde kodu yeniden kullanmanız
gerekiyorsa, Swift işlevlerini kullanabilirsiniz.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

Tuist, varsayılan olarak, oluşturulmuş projeyi ve bağımlılıklarının projelerini
içeren bir [Xcode Çalışma
Alanı](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
oluşturur. Herhangi bir nedenle çalışma alanını özelleştirerek ek projeler
eklemek veya dosya ve gruplar dahil etmek isterseniz, bunu
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
manifestosunu tanımlayarak yapabilirsiniz.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info
<!-- -->
Tuist, bağımlılık grafiğini çözecek ve bağımlılıkların projelerini çalışma
alanına dahil edecektir. Bunları manuel olarak eklemenize gerek yoktur. Bu,
derleme sisteminin bağımlılıkları doğru bir şekilde çözmesi için gereklidir.
<!-- -->
:::

### Çoklu veya tekli proje {#multi-or-monoproject}

Sıkça sorulan bir soru, bir çalışma alanında tek bir proje mi yoksa birden fazla
proje mi kullanılması gerektiğidir. Tuist'in olmadığı ve tek proje kurulumunun
sık sık Git çakışmalarına yol açtığı bir dünyada, çalışma alanlarının
kullanılması teşvik edilir. Ancak, Tuist tarafından oluşturulan Xcode
projelerinin Git deposuna dahil edilmesini önermediğimizden, Git çakışmaları
sorun teşkil etmez. Bu nedenle, bir çalışma alanında tek bir proje mi yoksa
birden fazla proje mi kullanacağınız kararı size kalmıştır.

Tuist projesinde, soğuk nesil süresi daha hızlı olduğu için (derlenecek daha az
manifest dosyası olduğu için) tekli projelere güveniyoruz ve
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklaması
yardımcıları</LocalizedLink>nı kapsülleme birimi olarak kullanıyoruz. Ancak,
uygulamanızın farklı alanlarını temsil etmek için Xcode projelerini kapsülleme
birimi olarak kullanmak isteyebilirsiniz, bu da Xcode'un önerdiği proje yapısına
daha yakındır.

## Tuist.swift {#tuistswift}

Tuist, proje yapılandırmasını basitleştirmek için
<LocalizedLink href="/contributors/principles.html#default-to-conventions">mantıklı
varsayılanlar</LocalizedLink> sağlar. Ancak, projenin kökünde
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
tanımlayarak yapılandırmayı özelleştirebilirsiniz. Bu dosya, Tuist tarafından
projenin kökünü belirlemek için kullanılır.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
