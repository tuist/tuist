---
{
  "title": "Bazel 프로젝트 마이그레이션",
  "titleTemplate": ":title · 마이그레이션 · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Bazel에서 Tuist로 프로젝트를 마이그레이션하는 방법을 알아보세요."
}
---
# Bazel 프로젝트 마이그레이션 {#migrate-a-bazel-project}

[Bazel](https://bazel.build)은 구글이 2015년에 오픈소스로 공개한 빌드 시스템입니다. 모든 규모의 소프트웨어를 빠르고 안정적으로 빌드하고 테스트할 수 있는 강력한 도구입니다. [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae), [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)와 같은 대형 조직에서 사용하고 있지만, 도입과 유지 관리를 위해서는 초기 투자(예: 기술 학습)와 지속적인 투자(예: Xcode 업데이트 대응)가 필요합니다. 이를 횡단 관심사로 다루는 일부 조직에는 적합하지만, 제품 개발에 집중하려는 다른 조직에는 최선의 선택이 아닐 수 있습니다. 예를 들어, iOS 플랫폼 팀이 Bazel을 도입했다가 주도했던 엔지니어들이 회사를 떠나면서 중단해야 했던 사례를 보았습니다. Xcode와 빌드 시스템 간의 강한 결합에 대한 Apple의 입장도 시간이 지남에 따라 Bazel 프로젝트를 유지하기 어렵게 만드는 또 다른 요인입니다.

> [!TIP]
> **Tuist의 독창성은 섬세함에 있습니다**
>
> Xcode와 Xcode 프로젝트와 싸우는 대신, Tuist는 이를 수용합니다. 동일한 개념(예: 타겟, 스킴, 빌드 설정), 친숙한 언어(즉, Swift), 그리고 간단하고 즐거운 경험을 제공하여 프로젝트 유지 관리와 확장을 iOS 플랫폼 팀뿐만 아니라 모두의 업무로 만듭니다.


## 규칙 {#rules}

Bazel은 규칙을 사용하여 소프트웨어를 빌드하고 테스트하는 방법을 정의합니다. 규칙은 Python과 유사한 언어인 [Starlark](https://github.com/bazelbuild/starlark)로 작성됩니다. Tuist는 구성 언어로 Swift를 사용하며, 이는 개발자에게 Xcode의 자동 완성, 타입 검사 및 검증 기능의 편의성을 제공합니다. 예를 들어, 다음 규칙은 Bazel에서 Swift 라이브러리를 빌드하는 방법을 설명합니다:

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

다음은 Bazel과 Tuist에서 단위 테스트를 정의하는 방법을 비교한 또 다른 예시입니다:

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Swift Package Manager 의존성 {#swift-package-manager-dependencies}

Bazel에서는 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 플러그인을 사용하여 Swift 패키지를 의존성으로 사용할 수 있습니다. 이 플러그인은 의존성의 신뢰할 수 있는 소스로 `Package.swift`가 필요합니다. Tuist의 인터페이스도 그 점에서 Bazel과 유사합니다. `tuist install` 명령을 사용하여 패키지의 의존성을 해결하고 가져올 수 있습니다. 해결이 완료되면 `tuist generate` 명령으로 프로젝트를 생성할 수 있습니다.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 프로젝트 생성 {#project-generation}

커뮤니티는 Bazel로 선언된 프로젝트에서 Xcode 프로젝트를 생성하기 위해 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)라는 규칙 세트를 제공합니다. Bazel에서는 `BUILD` 파일에 일부 구성을 추가해야 하지만, Tuist는 전혀 구성이 필요하지 않습니다. 프로젝트의 루트 디렉토리에서 `tuist generate`를 실행하면 Tuist가 Xcode 프로젝트를 생성해 줍니다.
