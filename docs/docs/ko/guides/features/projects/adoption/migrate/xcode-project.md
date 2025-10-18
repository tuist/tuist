---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcode 프로젝트 마이그레이션 {#migrate-an-xcode-project}

<LocalizedLink href="/guides/features/projects/adoption/new-project">Tuist를 사용해
새로운 프로젝트 생성</LocalizedLink>을 하지 않는다면 Tuist의 기본 구성 요소를 사용해 Xcode 프로젝트를 직접 정의해야
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

::: tip PROJECT NAME WITH -TUIST SUFFIX
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
tuist build -- ...{xcodebuild flags} # or tuist test
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
You can override the product type for a specific package by adding it to the
`productTypes` dictionary in the `PackageSettings` struct. By default, Tuist
assumes that all packages are static frameworks.
<!-- -->
:::


## Determine the migration order {#determine-the-migration-order}

We recommend migrating the targets from the one that is the most dependent upon
to the least. You can use the following command to list the targets of a
project, sorted by the number of dependencies:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Start migrating the targets from the top of the list, as they are the ones that
are the most depended upon.


## Migrate targets {#migrate-targets}

Migrate the targets one by one. We recommend doing a pull request for each
target to ensure that the changes are reviewed and tested before merging them.

### Extract the target build settings into `.xcconfig` files {#extract-the-target-build-settings-into-xcconfig-files}

Like you did with the project build settings, extract the target build settings
into an `.xcconfig` file to make the target leaner and easier to migrate. You
can use the following command to extract the build settings from the target into
an `.xcconfig` file:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Define the target in the `Project.swift` file {#define-the-target-in-the-projectswift-file}

Define the target in `Project.targets`:

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
If the target has an associated test target, you should define it in the
`Project.swift` file as well repeating the same steps.
<!-- -->
:::

### Validate the target migration {#validate-the-target-migration}

Run `tuist build` and `tuist test` to ensure the project builds and tests pass.
Additionally, you can use [xcdiff](https://github.com/bloomberg/xcdiff) to
compare the generated Xcode project with the existing one to ensure that the
changes are correct.

### Repeat {#repeat}

Repeat until all the targets are fully migrated. Once you are done, we recommend
updating your CI and CD pipelines to build and test the project using `tuist
build` and `tuist test` commands to benefit from the speed and reliability that
Tuist provides.

## Troubleshooting {#troubleshooting}

### Compilation errors due to missing files. {#compilation-errors-due-to-missing-files}

If the files associated to your Xcode project targets were not all contained in
a file-system directory representing the target, you might end up with a project
that doesn't compile. Make sure the list of files after generating the project
with Tuist matches the list of files in the Xcode project, and take the
opportunity to align the file structure with the target structure.
