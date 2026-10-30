---
{
  "title": "생성된 프로젝트 만들기",
  "titleTemplate": ":title · Xcode · 튜토리얼 · Tuist",
  "description": "첫 번째 Tuist 생성 Xcode 프로젝트를 만들고 종속성을 추가하는 방법을 알아보세요"
}
---
# 생성된 프로젝트 만들기 {#create-a-generated-project}

임의의 디렉터리나 기존 프로젝트 디렉터리에서 Tuist를 시작하는 가장 쉬운 방법:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

이 명령어는 <.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>를 만들거나 기존 Xcode 프로젝트 또는 워크스페이스를 통합하는 단계를 안내합니다. 또한 원격 서버에 설정을 연결하여 <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>, <.localized_link href="/guides/features/previews">previews</.localized_link>, <.localized_link href="/guides/features/package-registries/swift">registry</.localized_link>와 같은 기능에 액세스할 수 있도록 도와줍니다.

> [!NOTE]
> **기존 프로젝트 마이그레이션**
>
> 개발자 경험을 개선하고 <.localized_link href="/guides/features/cache">캐시</.localized_link>의 이점을 활용하기 위해 기존 프로젝트를 생성된 프로젝트로 마이그레이션하려면 <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">마이그레이션 가이드</.localized_link>를 확인하세요.


## 종속성 추가 {#add-dependencies}

프로젝트가 추가 기능을 제공하기 위해 서드파티 라이브러리에 의존하는 것은 일반적입니다. 이를 위해 다음 명령어를 실행하여 프로젝트를 편집할 때 최상의 경험을 얻으세요:

```bash
tuist edit
```

프로젝트 파일이 포함된 Xcode 프로젝트가 열립니다. `Package.swift`을 편집하고 다음을 추가하세요.

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

그런 다음 프로젝트의 애플리케이션 타겟을 편집하여 `Kingfisher`을 종속성으로 선언하세요:

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

그런 다음 `tuist install`을 실행하여 [Swift Package Manager](https://www.swift.org/documentation/package-manager/)를 사용해 종속성을 해결하고 가져옵니다.

> [!NOTE]
> **SPM을 종속성 해결 도구로 사용**
>
> Tuist가 권장하는 종속성 관리 방식은 Swift Package Manager(SPM)를 종속성 해결에만 사용합니다. Tuist는 이후 최대 구성 가능성과 제어를 위해 이를 Xcode 프로젝트 및 타겟으로 변환합니다.


## 프로젝트 시각화 {#visualize-the-project}

다음 명령어를 실행하여 프로젝트 구조를 시각화할 수 있습니다:

```bash
tuist graph
```

이 명령어는 프로젝트 디렉터리에 `graph.png` 파일을 출력하고 엽니다:

![프로젝트 그래프](/images/guides/quick-start/graph.png)

## 종속성 사용하기 {#use-the-dependency}

`tuist generate`을 실행하여 Xcode에서 프로젝트를 열고, `ContentView.swift` 파일에 다음과 같이 변경하세요:

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

Xcode에서 앱을 실행하면 URL에서 로드된 이미지를 볼 수 있습니다.
