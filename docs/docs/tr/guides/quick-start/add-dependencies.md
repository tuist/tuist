---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Bağımlılıklar ekleyin {#add-dependencies}

Projelerin ek işlevler sağlamak için üçüncü taraf kitaplıklarına bağlı olması
yaygın bir durumdur. Bunu yapmak için, projenizi en iyi şekilde düzenlemek üzere
aşağıdaki komutu çalıştırın:

```bash
tuist edit
```

Proje dosyalarınızı içeren bir Xcode projesi açılacaktır. `Package.swift`
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

Ardından, projenizdeki uygulama hedefini düzenleyerek `Kingfisher` bağımlılığı
olarak tanımlayın:

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

Ardından, [Swift package
Manager](https://www.swift.org/documentation/package-manager/) kullanarak
bağımlılıkları çözmek ve çekmek için `tuist install` komutunu çalıştırın.

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist, bağımlılıklar için önerilen yaklaşımda, bağımlılıkları çözmek için
yalnızca Swift package Manager (SPM) kullanır. Tuist daha sonra bunları maksimum
yapılandırılabilirlik ve kontrol için Xcode projeleri ve hedeflerine dönüştürür.
<!-- -->
:::

## Projeyi görselleştirin {#visualize-the-project}

Aşağıdaki komutu çalıştırarak proje yapısını görselleştirebilirsiniz:

```bash
tuist graph
```

Komut, projenin dizininde `graph.png` dosyasını açar ve görüntüler:

![Proje grafiği](/images/guides/quick-start/graph.png)

## Bağımlılığı kullanın {#use-the-dependency}

`komutunu çalıştırın. tuist generate` komutunu çalıştırarak projeyi Xcode'da
açın ve `ContentView.swift` dosyasında aşağıdaki değişiklikleri yapın:

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

Xcode'dan uygulamayı çalıştırın, URL'den yüklenen görüntüyü görmelisiniz.
