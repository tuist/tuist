---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# أضف التبعيات {#add-dependencies}

من الشائع أن تعتمد المشاريع على مكتبات طرف ثالث لتوفير وظائف إضافية. للقيام
بذلك، قم بتشغيل الأمر التالي للحصول على أفضل تجربة لتحرير مشروعك:

```bash
tuist edit
```

سيتم فتح مشروع Xcode يحتوي على ملفات مشروعك. قم بتحرير `Package.swift` وأضف

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

ثم قم بتحرير هدف التطبيق في مشروعك لإعلان `Kingfisher` كاعتمادية:

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

ثم قم بتشغيل `tuist install` لحل المشكلة وسحب التبعيات باستخدام [Swift Package
Manager](https://www.swift.org/documentation/package-manager/).

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
توصي Tuist باستخدام Swift Package Manager (SPM) فقط لحل التبعيات. ثم تقوم Tuist
بتحويلها إلى مشاريع Xcode وأهداف لتحقيق أقصى قدر من قابلية التكوين والتحكم.
<!-- -->
:::

## تصور المشروع {#visualize-the-project}

يمكنك تصور هيكل المشروع عن طريق تشغيل:

```bash
tuist graph
```

سيؤدي الأمر إلى إخراج وفتح ملف `graph.png` في دليل المشروع:

![مخطط المشروع](/images/guides/quick-start/graph.png)

## استخدم التبعية {#use-the-dependency}

قم بتشغيل `tuist generate` لفتح المشروع في Xcode، وقم بإجراء التغييرات التالية
على ملف `ContentView.swift`:

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

قم بتشغيل التطبيق من Xcode، وسترى الصورة محملة من عنوان URL.
