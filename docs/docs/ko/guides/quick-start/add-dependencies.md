---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "첫 번째 Swift 프로젝트에 의존성을 추가하는 방법을 배웁니다."
}
---
# 의존성 추가하기 {#add-dependencies}

프로젝트에서 추가 기능을 제공하기 위해 서드 파티 라이브러리에 의존하는 것은 일반적입니다. 의존성을 추가하기 위해서는 다음의 명령어를 수행하여 프로젝트를 편집합니다:

```bash
tuist edit
```

프로젝트 파일이 포함된 Xcode 프로젝트가 열립니다. `Package.swift`를 수정하고 추가

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

그런 다음에 프로젝트의 애플리케이션 타겟을 수정하여 의존성으로 `Kingfisher`를 선언합니다:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

그런 다음에 `tuist install`을 수행해서 [Swift Package Manager](https://www.swift.org/documentation/package-manager/)를 사용하여 의존성을 해결하고 가져옵니다.

> [!NOTE] 의존성 해결 도구로 SPM
> Tuist는 의존성을 해결하는 데에만 Swift Package Manager (SPM) 을 사용하도록 권장합니다. 그런 다음에 Tuist는 이를 최대한의 구성 가능성과 제어를 위해 Xcode 프로젝트와 타겟으로 변환합니다.

## 프로젝트 시각화 {#visualize-the-project}

다음 명령어를 통해 프로젝트를 시각화 할 수 있습니다:

```bash
tuist graph
```

이 명령어는 프로젝트의 디렉토리에 `graph.png` 파일을 생성하고 엽니다.

![Project graph](/images/guides/quick-start/graph.png)

## 의존성 사용 {#use-the-dependency}

Xcode에서 프로젝트를 열기 위해 `tuist generate`를 수행하고 `ContentView.swift` 파일에 다음의 변경 사항을 적용합니다:

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

Xcode에서 앱을 실행하고 URL로 이미지가 출력되는 것을 볼 수 있습니다.
