---
{
  "title": "Yeni bir proje oluşturun",
  "titleTemplate": ":title · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile yeni bir projenin nasıl oluşturulacağını öğrenin."
}
---
# Yeni bir proje oluşturun {#create-a-new-project}

Tuist ile yeni bir projeye başlamanın en doğrudan yolu `tuist init` komutunu kullanmaktır. Bu komut, projenizi kurmanızda size rehberlik eden etkileşimli bir CLI başlatır. İstendiğinde, "oluşturulmuş proje" seçeneğini seçtiğinizden emin olun.

Ardından `tuist edit` çalıştırarak <.localized_link href="/guides/features/projects/editing">projeyi düzenleyebilir</.localized_link> ve Xcode projeyi düzenleyebileceğiniz bir proje açar. Oluşturulan dosyalardan biri, projenizin tanımını içeren `Project.swift` dosyasıdır. Swift Package Manager'a aşinaysanız, bunu Xcode projelerinin diliyle yazılmış `Package.swift` olarak düşünebilirsiniz.

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

> [!NOTE]
> Bakım yükünü en aza indirmek için mevcut şablon listesini bilinçli olarak kısa tutuyoruz. Bir uygulamayı temsil etmeyen, örneğin bir framework gibi bir proje oluşturmak istiyorsanız, başlangıç noktası olarak `tuist init` kullanabilir ve ardından oluşturulan projeyi ihtiyaçlarınıza göre değiştirebilirsiniz.


## Projeyi manuel olarak oluşturma {#manually-creating-a-project}

Alternatif olarak, projeyi manuel olarak oluşturabilirsiniz. Bunu yalnızca Tuist ve kavramlarına zaten aşinaysanız öneririz. Yapmanız gereken ilk şey, proje yapısı için ek dizinler oluşturmaktır:

```bash
mkdir MyFramework
cd MyFramework
```

Ardından, Tuist'i yapılandıran ve Tuist'in projenin kök dizinini belirlemek için kullandığı bir `Tuist.swift` dosyası ile projenizin bildirileceği bir `Project.swift` dosyası oluşturun:

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

> [!WARNING]
> Tuist, projenizin kökünü belirlemek için `Tuist/` dizinini kullanır ve buradan diğer manifest dosyalarını aramak için dizinleri globlar. Bu dosyaları tercih ettiğiniz editörle oluşturmanızı öneririz; bu noktadan sonra projeyi Xcode ile düzenlemek için `tuist edit` kullanabilirsiniz.
