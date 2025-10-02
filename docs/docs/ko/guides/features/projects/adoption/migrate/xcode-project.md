---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcode 프로젝트 마이그레이션 {#migrate-an-xcode-project}

Tuist</LocalizedLink>를 사용하여 새 프로젝트를
<LocalizedLink href="/guides/start/new-project">로 생성하는 경우(이 경우 모든 것이 자동으로 구성되는
경우)가 아니라면 Tuist의 프리미티브를 사용하여 Xcode 프로젝트를 정의해야 합니다. 이 과정이 얼마나 지루한지는 프로젝트가 얼마나
복잡한지에 따라 달라집니다.

아시다시피 Xcode 프로젝트는 시간이 지남에 따라 디렉토리 구조와 일치하지 않는 그룹, 대상 간에 공유되는 파일, 존재하지 않는 파일을
가리키는 파일 참조(일부만 언급) 등으로 인해 지저분하고 복잡해질 수 있습니다. 이렇게 복잡성이 누적되면 프로젝트를 안정적으로 마이그레이션하는
명령을 제공하기가 어려워집니다.

또한 수동 마이그레이션은 프로젝트를 정리하고 간소화할 수 있는 훌륭한 연습입니다. 프로젝트에 참여하는 개발자뿐만 아니라 프로젝트를 더 빠르게
처리하고 인덱싱하는 Xcode도 고마워할 것입니다. Tuist를 완전히 도입하면 프로젝트가 일관되게 정의되고 단순하게 유지됩니다.

이러한 작업을 간소화하기 위해 사용자들로부터 받은 피드백을 바탕으로 몇 가지 지침을 알려드리고자 합니다.

## 프로젝트 스캐폴드 만들기 {#create-project-scaffold}

먼저 다음 Tuist 파일을 사용하여 프로젝트의 발판을 만드세요:

::: 코드 그룹

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

`Project.swift` 는 프로젝트를 정의하는 매니페스트 파일이고 `Package.swift` 는 종속성을 정의하는 매니페스트 파일입니다.
` Tuist.swift` 파일은 프로젝트에 대한 프로젝트 범위의 Tuist 설정을 정의할 수 있는 곳입니다.

> [팁] 프로젝트 이름에 -TUIST 접미사 추가 기존 Xcode 프로젝트와의 충돌을 방지하려면 프로젝트 이름에 `-Tuist` 접미사를
> 추가하는 것이 좋습니다. 프로젝트를 Tuist로 완전히 마이그레이션한 후에는 이 접미사를 삭제할 수 있습니다.

## CI에서 튜이스트 프로젝트 빌드 및 테스트 {#build-and-test-the-tuist-project-in-ci}

각 변경 사항의 마이그레이션이 유효한지 확인하려면 지속적 통합을 확장하여 매니페스트 파일에서 Tuist가 생성한 프로젝트를 빌드하고 테스트하는
것이 좋습니다:

```bash
tuist install
tuist generate
tuist build -- ...{xcodebuild flags} # or tuist test
```

## 프로젝트 빌드 설정을 `.xcconfig` 파일 {#extract-the-project-build-settings-into-xcconfig-files}로 추출합니다.

프로젝트에서 빌드 설정을 `.xcconfig` 파일로 추출하면 프로젝트를 더 간결하고 쉽게 마이그레이션할 수 있습니다. 다음 명령을 사용하여
프로젝트에서 빌드 설정을 `.xcconfig` 파일로 추출할 수 있습니다:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

그런 다음 `Project.swift` 파일이 방금 만든 `.xcconfig` 파일을 가리키도록 업데이트합니다:

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

그런 다음 지속적 통합 파이프라인을 확장하여 다음 명령을 실행하여 빌드 설정이 `.xcconfig` 파일에 직접 변경되도록 합니다:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 패키지 종속성 추출 {#extract-package-dependencies}

프로젝트의 모든 종속성을 `Tuist/Package.swift` 파일로 추출합니다:

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

> [!TIP] 제품 유형 특정 패키지의 제품 유형을 `PackageSettings` 구조의 `productTypes` 사전에 추가하여 재정의할
> 수 있습니다. 기본적으로 튜이스트는 모든 패키지가 정적 프레임워크라고 가정합니다.


## 마이그레이션 순서 결정 {#determine-the-migration-order}

종속성이 가장 큰 대상부터 가장 적은 대상까지 마이그레이션하는 것이 좋습니다. 다음 명령을 사용하여 프로젝트의 대상을 종속성 수에 따라 정렬하여
나열할 수 있습니다:

```bash
tuist migration list-targets -p Project.xcodeproj
```

가장 많이 의존하는 대상부터 목록의 맨 위에서 마이그레이션을 시작하세요.


## 대상 마이그레이션 {#migrate-targets}

대상을 하나씩 마이그레이션하세요. 각 대상에 대해 풀 리퀘스트를 수행하여 병합하기 전에 변경 사항을 검토하고 테스트하는 것이 좋습니다.

### 대상 빌드 설정을 `.xcconfig` 파일 {#extract-the-target-build-settings-into-xcconfig-files}로 추출합니다.

프로젝트 빌드 설정과 마찬가지로 대상 빌드 설정을 `.xcconfig` 파일로 추출하여 대상을 더 간결하고 쉽게 마이그레이션할 수 있도록
합니다. 다음 명령을 사용하여 대상에서 빌드 설정을 `.xcconfig` 파일로 추출할 수 있습니다:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` 파일 {#define-the-target-in-the-projectswift-file}에서 대상을 정의합니다.

`Project.targets` 에서 대상을 정의합니다:

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

> [참고] 테스트 대상 테스트 대상에 연결된 테스트 대상이 있는 경우 `Project.swift` 파일에서도 동일한 단계를 반복하여 정의해야
> 합니다.

### 대상 마이그레이션 유효성 검사 {#validate-the-target-migration}

`tuist build` 및 `tuist test` 를 실행하여 프로젝트 빌드 및 테스트가 통과되었는지 확인합니다. 또한
[xcdiff](https://github.com/bloomberg/xcdiff)을 사용하여 생성된 Xcode 프로젝트를 기존 프로젝트와
비교하여 변경 사항이 올바른지 확인할 수 있습니다.

### 반복 {#반복}

모든 대상이 완전히 마이그레이션될 때까지 반복합니다. 완료되면 CI 및 CD 파이프라인을 업데이트하여 `tuist build` 및 `tuist
test` 명령을 사용하여 프로젝트를 빌드하고 테스트하여 Tuist가 제공하는 속도와 안정성의 이점을 활용하는 것이 좋습니다.

## 문제 해결 {#문제 해결}

### 누락된 파일로 인한 컴파일 오류. {#컴파일 오류-누락된 파일로 인한 컴파일 오류}

Xcode 프로젝트 대상에 연결된 파일이 모두 대상을 나타내는 파일 시스템 디렉터리에 포함되어 있지 않은 경우 프로젝트가 컴파일되지 않을 수
있습니다. Tuist로 프로젝트를 생성한 후 파일 목록이 Xcode 프로젝트의 파일 목록과 일치하는지 확인하고 파일 구조를 대상 구조에 맞게
조정하세요.
