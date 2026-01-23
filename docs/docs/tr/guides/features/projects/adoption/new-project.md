---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Yeni bir proje oluşturun {#create-a-new-project}

Tuist ile yeni bir projeye başlamanın en basit yolu, `tuist init` komutunu
kullanmaktır. Bu komut, projenizi kurmanıza yardımcı olan etkileşimli bir CLI
başlatır. İstendiğinde, "Oluşturulmuş projele" oluşturma seçeneğini
seçtiğinizden emin olun.

Ardından, `tuist edit` komutunu çalıştırarak projeyi
<LocalizedLink href="/guides/features/projects/editing">düzenleyebilirsiniz</LocalizedLink>
ve Xcode, projeyi düzenleyebileceğiniz bir proje açacaktır. Oluşturulan
dosyalardan biri, projenizin tanımını içeren `Project.swift` dosyasıdır. Swift
paketi Yöneticisi'ne aşina iseniz, bunu `Package.swift` dosyası olarak düşünün,
ancak Xcode projelerinin dilini kullanarak.

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
Bakım yükünü en aza indirmek için kullanılabilir şablonların listesini kasıtlı
olarak kısa tutuyoruz. Uygulamayı temsil etmeyen bir proje, örneğin bir çerçeve
oluşturmak istiyorsanız, `tuist init` adresini başlangıç noktası olarak
kullanabilir ve ardından oluşturulmuş projeyi ihtiyaçlarınıza göre
değiştirebilirsiniz.
<!-- -->
:::

## Projeyi manuel olarak oluşturma {#manually-creating-a-project}

Alternatif olarak, projeyi manuel olarak da oluşturabilirsiniz. Bunu yalnızca
Tuist ve kavramlarına zaten aşina iseniz yapmanızı öneririz. Yapmanız gereken
ilk şey, proje yapısı için ek dizinler oluşturmaktır:

```bash
mkdir MyFramework
cd MyFramework
```

Ardından, Tuist'i yapılandıracak ve Tuist tarafından projenin kök dizinini
belirlemek için kullanılacak `Tuist.swift` dosyasını ve projenizin ilan
edileceği `Project.swift` dosyasını oluşturun.

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
buradan dizinleri tarayarak diğer manifest dosyalarını arar. Bu dosyaları tercih
ettiğiniz düzenleyiciyle oluşturmanızı öneririz. Bundan sonra, `tuist edit`
komutunu kullanarak projeyi Xcode ile düzenleyebilirsiniz.
<!-- -->
:::
