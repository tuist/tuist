---
title: Migrate a Bazel project
titleTemplate: :title · Migrate · Adoption · Projects · Develop · Guides · Tuist
description: Bazel에서 Tuist로 프로젝트를 마이그레이션 하는 방법을 배웁니다.
---

# Migrate a Bazel project {#migrate-a-bazel-project}

[Bazel](https://bazel.build)은 Google이 2015년에 오픈소스로 공개한 빌드 시스템입니다. Bazel은 어떤 크기의 소프트웨어에서도 빠르고 안정적으로 빌드와 테스트할 수 있는 강력한 툴입니다. [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae), 또는 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)와 같은 일부 대규모 조직에서는 Bazel을 사용하지만, Bazel을 도입하고 유지하는데 초기 투자 (즉, 기술 학습) 와 지속적인 투자 (즉, Xcode 업데이트 유지) 가 필요합니다. 일부 조직에서는 이를 범용적인 문제로 다루어 효과를 볼 수 있지만, 제품 개발에만 집중하길 원하는 조직에서는 최선의 선택이 아닐 수 있습니다. 예를 들어, iOS 플랫폼 팀이 Bazel을 도입했는데 이를 주도했던 개발자들이 회사를 떠난 후에 이를 포기해야 했던 조직을 본 적이 있습니다. 애플의 Xcode와 빌드 시스템 간의 강한 결합성도 Bazel 프로젝트를 유지하는데 어렵게 만드는 또 다른 요인입니다.

> [!TIP] TUIST의 독창성은 섬세함에 있다
> Tuist는 Xcode와 Xcode 프로젝트에 맞서기 보다는 그것을 받아들입니다. Tuist는 동일한 개념 (즉, 타겟, 스킴, 빌드 설정), 익숙한 언어 (즉, Swift), 그리고 프로젝트를 유지하고 확장하는 것을 iOS 플랫폼 팀 뿐만 아니라 모든 팀에게 간단하고 즐거운 경험을 제공합니다.

## 규칙 {#rules}

Bazel은 소프트웨어를 빌드하고 테스트하는 방식을 정의하는 규칙을 사용합니다. 이 규칙은 Python과 유사한 언어인 [Starlark](https://github.com/bazelbuild/starlark)로 작성되어 있습니다. Tuist는 구성 언어로 Swift를 사용하므로 개발자는 Xcode의 자동 완성, 타입 검사, 그리고 기능 검증을 사용할 수 있습니다. 예를 들어, 다음은 Bazel이 Swift 라이브러리를 빌드하는 규칙을 나타냅니다:

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

:::

다음은 Bazel과 Tuist에서 단위 테스트를 정의하는 방법을 비교한 또 다른 예시 입니다:

:::code-group

```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "io.tuist.MyLibraryTests",
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
            bundleId: "io.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```

:::

## Swift Package Manager 의존성 {#swift-package-manager-dependencies}

Bazel에서 Swift Package를 의존성으로 사용하기 위해 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 플로그인을 사용할 수 있습니다. 이 플러그인은 의존성에 대한 진실 공급원으로 `Package.swift`를 요구합니다. Tuist의 인터페이스는 Bazel과 유사합니다. `tuist install` 명령어를 사용하여 패키지의 의존성을 해결하고 가져올 수 있습니다. 의존성 해결이 완료되면 `tuist generate` 명령어로 프로젝트를 생성할 수 있습니다.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 프로젝트 생성 {#project-generation}

커뮤니티는 Bazel로 선언된 프로젝트를 Xcode 프로젝트를 생성하기 위해 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)라는 규칙을 제공합니다. `BUILD` 파일에 이불 구성을 추가해야 하는 Bazel과 달리, Tuist는 이런 구성이 필요하지 않습니다. 프로젝트의 루트 디렉토리에서 `tuist generate`를 수행하면 Tuist는 Xcode 프로젝트를 생성합니다.
