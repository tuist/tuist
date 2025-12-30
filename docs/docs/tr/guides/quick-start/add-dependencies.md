---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Bağımlılıkları ekleyin {#add-dependencies}

Projelerin ek işlevsellik sağlamak için üçüncü taraf kütüphanelere bağımlı
olması yaygın bir durumdur. Bunu yapmak için, projenizi düzenlerken en iyi
deneyimi elde etmek üzere aşağıdaki komutu çalıştırın:

```bash
tuist edit
```

Proje dosyalarınızı içeren bir Xcode projesi açılacaktır. ` Package.swift`
dosyasını düzenleyin ve

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

Ardından projenizdeki uygulama hedefini düzenleyerek `Kingfisher` adresini bir
bağımlılık olarak bildirin:

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
                .external(name: "Kingfisher") // [!code ++]
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

Ardından [Swift paketi Paket
Yöneticisi](https://www.swift.org/documentation/package-manager/) kullanarak
bağımlılıkları çözmek ve çekmek için `tuist install` adresini çalıştırın.

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist'in bağımlılıklar için önerdiği yaklaşım, bağımlılıkları çözmek için
yalnızca Swift paketi Paket Yöneticisini (SPM) kullanır. Tuist daha sonra
bunları maksimum yapılandırılabilirlik ve kontrol için Xcode projelerine ve
hedeflerine dönüştürür.
<!-- -->
:::

## Projeyi görselleştirin {#visualize-the-project}

Proje yapısını çalıştırarak görselleştirebilirsiniz:

```bash
tuist graph
```

Komut, projenin dizininde bir `graph.png` dosyası çıkaracak ve açacaktır:

![Proje grafiği](/images/guides/quick-start/graph.png)

## Bağımlılığı kullanın {#use-the-dependency}

Projeyi Xcode'da açmak için `tuist generate` adresini çalıştırın ve
`ContentView.swift` dosyasında aşağıdaki değişiklikleri yapın:

```swift
import SwiftUI
import Kingfisher // [!code ++]

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("Hello, World!") // [!code --]
            .padding() // [!code --]
        KFImage(URL(string: "https://cloud.tuist.io/images/tuist_logo_32x32@2x.png")!) // [!code ++]
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

Uygulamayı Xcode'dan çalıştırın ve URL'den yüklenen görüntüyü görmelisiniz.
