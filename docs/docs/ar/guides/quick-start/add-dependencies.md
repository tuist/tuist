---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# إضافة التبعيات {#add-dependencies}

من الشائع أن تعتمد المشاريع على مكتبات الطرف الثالث لتوفير وظائف إضافية. للقيام
بذلك، قم بتشغيل الأمر التالي للحصول على أفضل تجربة لتحرير مشروعك:

```bash
tuist edit
```

سيتم فتح مشروع Xcode يحتوي على ملفات مشروعك. قم بتحرير ملف `Package.swift.swift`
وأضف

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

ثم قم بتحرير هدف التطبيق في مشروعك للإعلان عن `Kingfisher` كتبعية:

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

ثم قم بتشغيل `tuist install` لحل وسحب التبعيات باستخدام [Swift Package Manager]
(https://www.swift.org/documentation/package-manager/).

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
النهج الموصى به من تويست للتبعيات يستخدم مدير حزم سويفت (SPM) فقط لحل التبعيات.
ثم يقوم تويست بتحويلها إلى مشاريع وأهداف Xcode لتحقيق أقصى قدر من التهيئة
والتحكم.
<!-- -->
:::

## تصور المشروع {#visualize-the-project}

يمكنك تصور بنية المشروع من خلال تشغيل:

```bash
tuist graph
```

سيقوم الأمر بإخراج وفتح ملف `graph.png.png` في دليل المشروع:

![الرسم البياني للمشروع] (/images/guides/quick-start/graph.png)

## استخدام التبعية {#use-the-dependency}

قم بتشغيل `tuist توليد` لفتح المشروع في Xcode، وقم بإجراء التغييرات التالية على
ملف `ContentView.swift.swift`

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

شغِّل التطبيق من Xcode، وسترى الصورة محمَّلة من عنوان URL.
