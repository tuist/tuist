---
title: 기존 Xcode 프로젝트를 Tuist로 전환하기
titleTemplate: :title · Migrate · Adoption · Projects · Develop · Guides · Tuist
description: Xcode 프로젝트에서 Tuist 프로젝트로 변환하는 방법을 알아봅니다.
---

# Migrate an Xcode project {#migrate-an-xcode-project}

<LocalizedLink href="/guides/start/new-project">Tuist로 새로운 프로젝트를 생성</LocalizedLink>하면 자동으로 모든 것이 구성되지만 그렇지 않으면, Tuist의 기본 요소를 사용해서 Xcode 프로젝트를 정의해야 합니다. 이 과정이 얼마나 번거로운지는 프로젝트의 복잡도에 따라 다릅니다.

이미 알고 있지만, Xcode 프로젝트는 시간이 지날 수록 복잡하고 정리가 안될 수 있습니다: 디렉토리 구조와 맞지않는 그룹, 여러 타겟에서 공유되는 파일 또는 존재하지 않는 파일에 대한 참조가 그 예시입니다. 그렇게 쌓인 복잡성은 프로젝트를 신뢰성 있게 마이그레이션하는 명령어를 제공하는 것이 어렵습니다.

게다가 수동 마이그레이션은 프로젝트를 정리하고 단순화하는데 매우 좋은 연습입니다. 개발자들 뿐만 아니라 Xcode도 프로젝트의 처리와 인덱싱하는 속도가 빨라져서 감사할 것입니다. Tuist를 완전히 도입하면, 프로젝트가 일관되게 정의되고 단순하게 유지되도록 보장합니다.

해당 작업을 수월하게 하기 위해 우리는 사용자에게 받은 피드백을 기반으로 한 몇 가지 지침을 제공합니다.

## 프로젝트 생성 {#create-project-scaffold}

먼저, 다음의 Tuist 파일들을 생성해서 프로젝트의 구조를 잡아줍니다:

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

:::

`Project.swift`는 프로젝트를 정의하는 매니페스트 파일이며, `Package.swift`는 의존성을 정의하는 매니페스트 파일입니다. `Tuist.swift` 파일은 현재 프로젝트의 Tuist 설정을 정의할 수 있습니다.

> [!TIP] -TUIST 접미사가 붙은 프로젝트 이름\
> 기존에 Xcode 프로젝트의 충돌을 방지하기 위해 프로젝트 이름에 `-Tuist` 접미사를 추가하는 것이 좋습니다. 프로젝트를 Tuist로 완전히 마이그레이션 하면 삭제할 수 있습니다.

## CI에서 Tuist 프로젝트 빌드와 테스트 {#build-and-test-the-tuist-project-in-ci}

각 변경 사항의 마이그레이션 유효성을 보장하기 위해, Tuist가 매니페스트 파일로 생성한 프로젝트를 빌드하고 테스트하는 CI를 확장하는 것이 좋습니다.

```bash
tuist install
tuist generate
tuist build -- ...{xcodebuild flags} # or tuist test
```

## `.xcconfig` 파일로 프로젝트 빌드 설정 추출 {#extract-the-project-build-settings-into-xcconfig-files}

프로젝트를 더 가볍고 마이그레이션하기 쉽게 만들기 위해 `.xcconfig` 파일로 프로젝트 빌드 설정을 추출합니다. `.xcconfig` 파일로 프로젝트 빌드 설정을 추출하기 위해 아래의 명령어를 사용할 수 있습니다:

```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

그런 다음 `Project.swift` 파일에 생성된 `.xcconfig` 파일의 위치를 작성합니다:

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

그런 다음 CI 파이프라인을 확장하여 다음 명령어를 수행해서 빌드 설정의 변경 사항을 직접 `.xcconfig` 파일에 작성하도록 합니다:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 패키지 의존성 추출 {#extract-package-dependencies}

프로젝트의 모든 의존성을 `Tuist/Package.swift` 파일로 추출합니다:

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

> [!TIP] PRODUCT TYPES\
> `PackageSettings` 구조체의 `productTypes` 딕셔너리에 특정 패키지에 대한 제품 타입을 재정의할 수 있습니다. 기본적으로 Tuist는 모든 패키지가 정적 프레임워크로 간주합니다.

## 마이그레이션 순서 {#determine-the-migration-order}

가장 의존도가 높은 타겟에서 가장 의존도가 낮은 타겟 순으로 마이그레이션 하는 것이 좋습니다. 다음 명령어를 수행하면 프로젝트의 타겟이 의존도에 따라 정렬되어 나타납니다:

```bash
tuist migration list-targets -p Project.xcodeproj
```

위에 있는 타겟이 의존도가 높으므로 이 타겟부터 마이그레이션 합니다.

## 타겟 마이그레이션 {#migrate-targets}

타겟을 하나씩 마이그레이션 합니다. 변경 사항을 병합하기 전에 검토되고 테스트 되기위해 각 타겟에 대해 Pull Request를 수행하는 것이 좋습니다.

### 타겟 빌드 설정을 `.xcconfig` 파일로 추출 {#extract-the-target-build-settings-into-xcconfig-files}

프로젝트 빌드 설정과 마찬가지로, 타겟을 더 가볍고 마이그레이션하기 쉽게 만들기 위해 타겟 빌드 설정을 `.xcconfig` 파일로 추출합니다. 다음 명령어를 수행하면 타겟의 빌드 설정을 `.xcconfig` 파일로 추출합니다:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` 파일에 타겟 정의 {#define-the-target-in-the-projectswift-file}

`Project.targets` 에 타겟을 정의합니다:

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
            bundleId: "io.tuist.targetX", // [!code ++]
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

> [!NOTE] TEST TARGETS
> 타겟과 연관있는 테스트 타겟이 존재하면, `Project.swift` 파일에 동일하게 해당 타겟을 정의해야 합니다.

### 타겟 마이그레이션 검증 {#validate-the-target-migration}

`tuist build`와 `tuist test`를 수행해서 프로젝트 빌드와 테스트가 통과되는지 확인합니다. 또한, [xcdiff](https://github.com/bloomberg/xcdiff)을 사용하여 생성된 Xcode 프로젝트와 기존 프로젝트의 변경사항이 맞는지 비교할 수 있습니다.

### 반복 {#repeat}

모든 타겟이 마이그레이션 할 때까지 반복합니다. 작업이 완료되면, Tuist가 제공하는 속도와 안정성의 이점을 위해 `tuist build`와 `tuist test` 명령어를 사용하여 프로젝트 빌드와 테스트를 할 수 있게 CI와 CD 파이프라인을 업데이트 하는 것이 좋습니다.

## 문제 해결 {#troubleshooting}

### 파일 누락으로 인한 컴파일 오류 파일 누락으로 인한 컴파일 오류 파일 누락으로 인한 컴파일 오류 {#compilation-errors-due-to-missing-files} 파일 누락으로 인한 컴파일 오류 파일 누락으로 인한 컴파일 오류 {#compilation-errors-due-to-missing-files} 파일 누락으로 인한 컴파일 오류 파일 누락으로 인한 컴파일 오류 {#compilation-errors-due-to-missing-files}

Xcode 프로젝트 타겟에 연관된 파일이 마이그레이션 한 타겟 파일 시스템 디렉토리에 포함되지 않으면, 그 프로젝트는 컴파일되지 않습니다. Tuist로 프로젝트를 생성한 후에 Xcode 프로젝트의 파일 목록과 일치하는지 확인하고, 타겟 구조와 파일 구조를 일치 시킵니다.
