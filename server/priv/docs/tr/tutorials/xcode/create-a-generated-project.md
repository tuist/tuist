---
{
  "title": "Oluşturulmuş bir proje oluşturun",
  "titleTemplate": ":title · Xcode · Eğitimler · Tuist",
  "description": "İlk Tuist tarafından oluşturulan Xcode projenizi nasıl oluşturacağınızı ve ona bağımlılıklar ekleyeceğinizi öğrenin"
}
---
# Oluşturulmuş bir proje oluşturun {#create-a-generated-project}

Boş bir dizinde veya mevcut bir projenin dizininde `tuist init` komutunu çalıştırın:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Komut, <.localized_link href="/guides/features/projects">oluşturulmuş bir proje oluşturmak</.localized_link> veya mevcut bir Xcode projesini ya da çalışma alanını entegre etmek için gereken adımlarda size rehberlik eder. Kurulumunuzu uzak sunucuya bağlamanıza yardımcı olur ve <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link>, <.localized_link href="/guides/features/previews">önizlemeler</.localized_link> ile <.localized_link href="/guides/features/package-registries/swift">kayıt defteri</.localized_link> gibi özelliklere erişim sağlar.

> [!NOTE]
> **Mevcut bir projeyi taşıyın**
>
> Geliştirici deneyimini iyileştirmek ve <.localized_link href="/guides/features/cache">önbelleğimizden</.localized_link> yararlanmak amacıyla mevcut bir projeyi oluşturulmuş projelere taşımak istiyorsanız <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">taşıma kılavuzumuza</.localized_link> göz atın.


## Bağımlılıkları ekleyin {#add-dependencies}

Projelerin ek işlevsellik sağlamak için üçüncü taraf kütüphanelere bağımlı olması yaygındır. Bunu yapmak için projenizi düzenlerken en iyi deneyimi elde etmek üzere aşağıdaki komutu çalıştırın:

```bash
tuist edit
```

Proje dosyalarınızı içeren bir Xcode projesi açılır. `Tuist/Package.swift` dosyasını düzenleyin ve Kingfisher'ı ekleyin:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

Ardından, projenizdeki uygulama hedefini düzenleyerek `Kingfisher` öğesini bağımlılık olarak bildirin:

```swift
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
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            buildableFolders: [
                "MyApp/Sources",
                "MyApp/Resources",
            ],
            dependencies: [
                .external(name: "Kingfisher")
            ]
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

Ardından, bağımlılıkları çözmek ve indirmek için `tuist install` komutunu çalıştırın; bu işlem [Swift Package Manager](https://www.swift.org/documentation/package-manager/) kullanılarak yapılır.

> [!NOTE]
> **Bağımlılık çözümleyici olarak SwiftPM**
>
> Tuist'in önerilen bağımlılık yaklaşımı, Swift Package Manager'ı (SPM) yalnızca bağımlılıkları çözmek için kullanır. Tuist daha sonra bunları maksimum yapılandırılabilirlik ve kontrol sağlamak amacıyla Xcode projelerine ve hedeflerine dönüştürür.


## Projeyi görselleştirin {#visualize-the-project}

Şu komutu çalıştırarak proje yapısını görselleştirebilirsiniz:

```bash
tuist graph
```

Komut, projenin dizininde bir `graph.png` dosyası oluşturur ve açar:

![Proje grafiği](/images/guides/quick-start/graph.png)

## Bağımlılığı kullanın {#use-the-dependency}

Projeyi Xcode'da açmak için `tuist generate` komutunu çalıştırın ve `ContentView.swift` dosyasında aşağıdaki değişiklikleri yapın:

```swift
import SwiftUI
import Kingfisher

public struct ContentView: View {
    public init() {}

    public var body: some View {
        KFImage(URL(string: "https://tuist.dev/images/tuist_logo_32x32@2x.png")!)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

Uygulamayı Xcode'dan çalıştırın; URL'den yüklenen görüntüyü görmeniz gerekir.
