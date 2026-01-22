---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 의존성 추가 {#add-dependencies}

프로젝트가 추가 기능을 제공하기 위해 타사 라이브러리에 의존하는 것은 흔한 일입니다. 이를 위해 프로젝트 편집 시 최적의 환경을 제공받으려면
다음 명령어를 실행하세요:

```bash
tuist edit
```

Xcode 프로젝트가 열리면 프로젝트 파일이 포함되어 있습니다. Package.swift( `)를 편집하고 다음을 추가하세요.`

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

그런 다음 프로젝트의 애플리케이션 타깃을 편집하여 `Kingfisher` 를 종속성으로 선언하십시오:

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

그런 다음 `tuist install` 를 실행하여 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)을 사용하여 종속성을 해결하고
가져옵니다.

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist가 권장하는 종속성 관리 방식은 Swift Package Manager(SPM)를 종속성 해결에만 사용합니다. 이후 Tuist는 최대의
구성 가능성과 제어력을 위해 이를 Xcode 프로젝트 및 타깃으로 변환합니다.
<!-- -->
:::

## 프로젝트 시각화 {#visualize-the-project}

다음 명령어를 실행하여 프로젝트 구조를 시각화할 수 있습니다:

```bash
tuist graph
```

이 명령어는 프로젝트 디렉토리에 `graph.png` 파일을 출력하고 엽니다:

![프로젝트 그래프](/images/guides/quick-start/graph.png)

## 의존성을 사용하십시오 {#use-the-dependency}

`를 실행하세요. tuist generate` 를 실행하여 Xcode에서 프로젝트를 열고, `ContentView.swift 파일(` )에서
다음 변경 사항을 적용하세요:

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

Xcode에서 앱을 실행하면 URL에서 로드된 이미지가 표시됩니다.
