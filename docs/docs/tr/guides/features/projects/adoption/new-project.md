---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Yeni bir proje oluşturun {#create-a-new-project}

Tuist ile yeni bir proje başlatmanın en kolay yolu `tuist init` komutunu
kullanmaktır. Bu komut, projenizi kurarken size rehberlik eden etkileşimli bir
CLI başlatır. Sorulduğunda, "oluşturulmuş projele" oluşturma seçeneğini
seçtiğinizden emin olun.

Daha sonra <LocalizedLink href="/guides/features/projects/editing"> projeyi düzenleyebilir</LocalizedLink> `tuist edit` çalıştırabilirsiniz ve Xcode projeyi
düzenleyebileceğiniz bir proje açacaktır. Oluşturulan dosyalardan biri,
projenizin tanımını içeren `Project.swift` dosyasıdır. Swift paketi Yöneticisine
aşinaysanız, bunu `Package.swift` gibi düşünün, ancak Xcode projelerinin
diliyle.

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

::: info
<!-- -->
Bakım yükünü en aza indirmek için mevcut şablonların listesini kasıtlı olarak
kısa tutuyoruz. Bir uygulamayı temsil etmeyen bir proje, örneğin bir çerçeve
oluşturmak istiyorsanız, başlangıç noktası olarak `tuist init` adresini
kullanabilir ve ardından oluşturulmuş projele ihtiyaçlarınıza uyacak şekilde
değiştirebilirsiniz.
<!-- -->
:::

## Manuel olarak proje oluşturma {#manually-creating-a-project}

Alternatif olarak, projeyi manuel olarak da oluşturabilirsiniz. Bunu yalnızca
Tuist ve kavramlarına zaten aşina iseniz yapmanızı öneririz. Yapmanız gereken
ilk şey, proje yapısı için ek dizinler oluşturmaktır:

```bash
mkdir MyFramework
cd MyFramework
```

Ardından, Tuist'i yapılandıracak ve Tuist tarafından projenin kök dizinini
belirlemek için kullanılan bir `Tuist.swift` dosyası ve projenizin beyan
edileceği bir `Project.swift` dosyası oluşturun:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

::: warning
<!-- -->
Tuist, projenizin kök dizinini belirlemek için `Tuist/` dizinini kullanır ve
buradan dizinleri globlayan diğer manifesto dosyalarını arar. Bu dosyaları
tercih ettiğiniz editörle oluşturmanızı öneririz ve bu noktadan sonra projeyi
Xcode ile düzenlemek için `tuist edit` adresini kullanabilirsiniz.
<!-- -->
:::
