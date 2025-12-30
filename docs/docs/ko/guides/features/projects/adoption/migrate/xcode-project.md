---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcode 프로젝트 마이그레이션 {#migrate-an-xcode-project}

<LocalizedLink href="/guides/features/projects/adoption/new-project">Tuist를 사용해 새로운 프로젝트 생성</LocalizedLink>을 하지 않는다면 Tuist의 기본 구성 요소를 사용해 Xcode 프로젝트를 직접 정의해야
합니다. 이 과정이 얼마나 번거로운지는 프로젝트의 복잡도에 따라 달라집니다.

이미 알고 있듯이, Xcode 프로젝트는 시간이 지남에 따라 더 복잡하고 어려워질 수 있습니다: 디렉토리 구조와 일치하지 않는 그룹, 여러 타겟
간에 공유되는 파일, 존재하지 않는 파일 참조 등이 그 예입니다. 이러한 모든 복잡성은 프로젝트를 안정적으로 마이그레이션하는 명령어를 제공하기가
어렵습니다.

수동 마이그레이션은 프로젝트를 정리하고 단순화하는데 좋은 기회이기도 합니다. 프로젝트의 개발자 뿐만 아니라 프로젝트를 더 빠르게 처리하고
인덱싱할 수 있는 Xcode에도 도움이 됩니다. Tuist를 적용한 후에는 프로젝트가 일관되게 정의되고 단순한 상태를 유지하도록 보장합니다.

이 작업을 좀 더 쉽게 하기위해 사용자로부터 받은 피드백 기준으로 몇 가지 라이드라인을 제공합니다.

## 프로젝트 기본 구조 생성 {#create-project-scaffold}

먼저 다음의 Tuist 파일로 프로젝트의 기본 구조를 생성합니다:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
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
    ]
)
```
<!-- -->
:::

`Project.swift`는 프로젝트를 정의하는 매니페스트 파일이며 `Package.swift`는 의존성을 정의하는 매니페스트 파일입니다.
`Tuist.swift`는 프로젝트 범위에서 Tuist 설정을 정의할 수 있는 파일입니다.

::: tip 프로젝트 이름에 접미사 TUIST
<!-- -->
기존 Xcode 프로젝트에서 충돌을 방지하기 위해 프로젝트 이름 뒤에 `-Tuist` 접미사를 붙이길 권장합니다. 프로젝트를 Tuist로 완전히
마이그레이션한 후에 이를 제거할 수 있습니다.
<!-- -->
:::

## CI에서 Tuist 프로젝트 빌드와 테스트 {#build-and-test-the-tuist-project-in-ci}

각 변경 사항의 마이그레이션이 유효한지 확인하기 위해 매니페스트 파일로부터 Tuist가 생성한 프로젝트를 빌드하고 테스트하도록 CI 확장을
권장합니다:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 프로젝트 빌드 설정을 `.xcconfig` 파일로 분리 {#extract-the-project-build-settings-into-xcconfig-files}

프로젝트의 빌드 설정을 `.xcconfig` 파일로 분리하면 프로젝트는 더 간결하고 마이그레이션하기 쉬워집니다. 다음 명령어를 사용해 프로젝트의
빌드 설정을 `.xcconfig` 파일로 분리할 수 있습니다:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

그런 다음에 방금 생성된 `.xcconfig` 파일을 참조하도록 `Project.swift` 파일을 업데이트합니다:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

그런 다음에 빌드 설정 변경이 직접적으로 `.xcconfig` 파일에 적용되기 위해 다음 명령어를 수행하도록 CI 파이프라인을 확장합니다:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 패키지 의존성 분리 {#extract-package-dependencies}

프로젝트의 모든 의존성을 `Tuist/Package.swift` 파일로 분리합니다:

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

::: tip PRODUCT TYPES
<!-- -->
특정 패키지의 타입을 재정의하려면 `PackageSettings` 구조체의 `productTypes` 딕셔너리에 해당 패키지를 추가합니다.
기본적으로 Tuist는 모든 패키지가 정적 프레임워크라고 가정합니다.
<!-- -->
:::


## 마이그레이션 순서 결정 {#determine-the-migration-order}

의존성이 많은 타겟부터 가장 적은 순으로 마이그레이션하는 것을 추천합니다. 다음 명령어를 사용해 의존성 개수에 따라 정렬된 프로젝트의 타겟
목록을 확인할 수 있습니다:

```bash
tuist migration list-targets -p Project.xcodeproj
```

목록의 가장 위에 있는 타겟이 의존성이 가장 많으므로 위에서 부터 마이그레이션을 시작합니다.


## 타겟 마이그레이션 {#migrate-targets}

타겟을 하나씩 마이그레이션합니다. 각 타겟의 풀 리퀘스트를 생성하여 변경사항이 머지되기 전에 검토와 테스트가 이루어지는 것을 권장합니다.

### 타겟 빌드 설정을 `.xcconfig` 파일로 추출 {#extract-the-target-build-settings-into-xcconfig-files}

프로젝트 빌드 설정에서 했던 것처럼 타겟 빌드 설정을 `.xcconfig` 파일로 추출하여 타겟을 더 간결하고 마이그레이션하기 쉽게 만듭니다.
다음 명령어를 사용하여 타겟의 빌드 설정에서 `.xcconfig` 파일을 추출합니다:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` 파일에 타겟 정의 {#define-the-target-in-the-projectswift-file}

`Project.targets`에 타겟 정의:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
타겟의 테스트 타겟을 가지고 있다면 동일하게 `Project.swift` 파일에 정의합니다.
<!-- -->
:::

### 타겟 마이그레이션 검증 {#validate-the-target-migration}

`tuist generate` 를 실행한 다음 `xcodebuild build` 를 실행하여 프로젝트가 빌드되는지 확인하고 `tuist
test` 를 실행하여 테스트가 통과되었는지 확인합니다. 또한
[xcdiff](https://github.com/bloomberg/xcdiff)을 사용하여 생성된 Xcode 프로젝트를 기존 프로젝트와
비교하여 변경 사항이 올바른지 확인할 수 있습니다.

### 반복 {#repeat}

모든 대상이 완전히 마이그레이션될 때까지 반복합니다. 완료되면 CI 및 CD 파이프라인을 업데이트하여 `tuist 생성` 다음
`xcodebuild 빌드` 및 `tuist 테스트` 를 사용하여 프로젝트를 빌드하고 테스트하는 것이 좋습니다.

## 문제 해결 {#troubleshooting}

### 파일 누락으로 인한 컴파일 오류. {#compilation-errors-due-to-missing-files}

Xcode 프로젝트 타겟에 연관된 파일이 타겟에 포함되지 않는 경우 컴파일되지 않는 프로젝트가 생성될 수 있습니다. Tuist로 프로젝트를
생성한 후에 파일 목록이 Xcode 프로젝트의 파일 목록과 일치하는지 확인하고 이 기회에 파일 구조를 타겟 구조와 일치하도록 정리하는 것을
추천합니다.
