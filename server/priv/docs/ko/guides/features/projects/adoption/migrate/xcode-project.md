---
{
  "title": "Xcode 프로젝트 마이그레이션",
  "titleTemplate": ":title · 마이그레이션 · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Xcode 프로젝트를 Tuist 프로젝트로 마이그레이션하는 방법을 알아보세요."
}
---
# Xcode 프로젝트 마이그레이션 {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuist를 사용해 새 프로젝트를 생성</.localized_link>하지 않는 한, Tuist의 기본 요소를 사용하여 Xcode 프로젝트를 정의해야 합니다. 이 과정이 얼마나 번거로운지는 프로젝트의 복잡도에 따라 달라집니다.

아시다시피, Xcode 프로젝트는 시간이 지남에 따라 복잡하고 지저분해질 수 있습니다. 디렉터리 구조와 일치하지 않는 그룹, 여러 타겟에서 공유되는 파일, 존재하지 않는 파일을 가리키는 파일 참조 등이 그 예입니다. 이렇게 누적된 복잡성으로 인해 프로젝트를 안정적으로 마이그레이션하는 명령어를 제공하기 어렵습니다.

또한 수동 마이그레이션은 프로젝트를 정리하고 단순화하는 데 매우 좋은 연습입니다. 프로젝트의 개발자들뿐만 아니라 처리 및 인덱싱 속도가 빨라지는 Xcode에도 도움이 됩니다. Tuist를 완전히 도입하면 프로젝트가 일관되게 정의되고 단순하게 유지됩니다.

이 작업을 쉽게 하기 위해 사용자 피드백을 바탕으로 몇 가지 가이드라인을 제공합니다.

## 프로젝트 스캐폴드 생성 {#create-project-scaffold}

먼저 다음 Tuist 파일로 프로젝트의 스캐폴드를 생성하세요:

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

`Project.swift`은 프로젝트를 정의하는 매니페스트 파일이고, `Package.swift`은 의존성을 정의하는 매니페스트 파일입니다. `Tuist.swift` 파일에서는 프로젝트 범위 Tuist 설정을 정의할 수 있습니다.

> [!TIP]
> **프로젝트 이름에 -Tuist 접미사 추가**
>
> 기존 Xcode 프로젝트와의 충돌을 방지하기 위해 프로젝트 이름에 `-Tuist` 접미사를 추가하는 것을 권장합니다. Tuist로 프로젝트를 완전히 마이그레이션한 후에는 이 접미사를 제거해도 됩니다.


## CI에서 Tuist 프로젝트 빌드 및 테스트 {#build-and-test-the-tuist-project-in-ci}

각 변경 사항의 마이그레이션이 유효한지 확인하려면, 매니페스트 파일로부터 Tuist가 생성한 프로젝트를 빌드하고 테스트하도록 지속적 통합(CI)을 확장하는 것을 권장합니다:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 프로젝트 빌드 설정을 `.xcconfig` 파일로 추출 {#extract-the-project-build-settings-into-xcconfig-files}

프로젝트를 더 가볍고 마이그레이션하기 쉽게 만들기 위해 빌드 설정을 `.xcconfig` 파일로 추출하세요. 다음 명령어를 사용하여 프로젝트의 빌드 설정을 `.xcconfig` 파일로 추출할 수 있습니다:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

그런 다음 방금 생성한 `.xcconfig` 파일을 가리키도록 `Project.swift` 파일을 업데이트하세요:

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

그리고 빌드 설정 변경 사항이 직접 `.xcconfig` 파일에 적용되도록 하려면 다음 명령어를 실행하도록 지속적 통합 파이프라인을 확장하세요:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 패키지 의존성 추출 {#extract-package-dependencies}

프로젝트의 모든 의존성을 `Tuist/Package.swift` 파일로 추출하세요:

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

> [!TIP]
> **제품 유형**
>
> 특정 패키지의 제품 유형을 재정의하려면 `PackageSettings` 구조체의 `productTypes` 딕셔너리에 추가하면 됩니다. 기본적으로 Tuist는 모든 패키지를 정적 프레임워크로 간주합니다.


## 마이그레이션 순서 결정 {#determine-the-migration-order}

가장 많이 의존되는 타겟부터 가장 적게 의존되는 타겟 순으로 마이그레이션하는 것을 권장합니다. 다음 명령어를 사용하여 의존성 수에 따라 정렬된 프로젝트 타겟 목록을 확인할 수 있습니다:

```bash
tuist migration list-targets -p Project.xcodeproj
```

목록의 맨 위에 있는 타겟부터 마이그레이션을 시작하세요. 이들은 가장 많이 의존되는 타겟입니다.


## 타겟 마이그레이션 {#migrate-targets}

타겟을 하나씩 마이그레이션하세요. 각 타겟에 대해 풀 리퀘스트를 만들어 병합 전에 변경 사항을 검토하고 테스트하는 것을 권장합니다.

### 타겟 빌드 설정을 `.xcconfig` 파일로 추출 {#extract-the-target-build-settings-into-xcconfig-files}

프로젝트 빌드 설정과 마찬가지로, 타겟 빌드 설정을 `.xcconfig` 파일로 추출하여 타겟을 더 가볍고 마이그레이션하기 쉽게 만드세요. 다음 명령어를 사용하여 타겟의 빌드 설정을 `.xcconfig` 파일로 추출할 수 있습니다:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` 파일에서 타겟 정의 {#define-the-target-in-the-projectswift-file}

`Project.targets`에서 타겟을 정의하세요:

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

> [!NOTE]
> **테스트 타겟**
>
> 타겟에 연결된 테스트 타겟이 있는 경우, 동일한 단계를 반복하여 `Project.swift` 파일에도 정의해야 합니다.


### 타겟 마이그레이션 검증 {#validate-the-target-migration}

프로젝트가 빌드되는지 확인하기 위해 `tuist generate`를 실행한 후 `xcodebuild build`를 실행하고, 테스트가 통과하는지 확인하기 위해 `tuist test`를 실행하세요. 또한 [xcdiff](https://github.com/bloomberg/xcdiff)를 사용하여 생성된 Xcode 프로젝트와 기존 프로젝트를 비교해 변경 사항이 올바른지 확인할 수 있습니다.

### 반복 {#repeat}

모든 타겟이 완전히 마이그레이션될 때까지 반복하세요. 완료되면 CI 및 CD 파이프라인을 업데이트하여 `tuist generate`를 실행한 후 `xcodebuild build`와 `tuist test`를 사용하여 프로젝트를 빌드하고 테스트하는 것을 권장합니다.

## 문제 해결 {#troubleshooting}

### 누락된 파일로 인한 컴파일 오류 {#compilation-errors-due-to-missing-files}

Xcode 프로젝트 타겟과 관련된 파일들이 타겟을 나타내는 파일 시스템 디렉터리에 모두 포함되어 있지 않다면, 컴파일되지 않는 프로젝트가 될 수 있습니다. Tuist로 프로젝트를 생성한 후 파일 목록이 Xcode 프로젝트의 파일 목록과 일치하는지 확인하고, 파일 구조를 타겟 구조와 일치시킬 기회를 활용하세요.
