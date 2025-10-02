---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazel 프로젝트 마이그레이션 {#migrate-a-bazel-project}

[바젤](https://bazel.build)은 Google이 2015년에 오픈소스화한 빌드 시스템입니다. 모든 규모의 소프트웨어를 빠르고
안정적으로 빌드하고 테스트할 수 있는 강력한 도구입니다.
Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae),
[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)와 같은 일부 대규모 조직에서 사용하고
있지만, 도입 및 유지 관리를 위해 사전 투자(기술 학습)와 지속적인 투자(Xcode 업데이트 따라잡기)가 필요합니다. 이러한 방식은 여러
부서를 아우르는 문제로 취급하는 일부 조직에는 적합하지만, 제품 개발에 집중하려는 다른 조직에는 적합하지 않을 수 있습니다. 예를 들어, iOS
플랫폼 팀에서 바젤을 도입했다가 이를 주도한 엔지니어가 회사를 떠난 후 이를 중단해야 했던 조직을 본 적이 있습니다. Xcode와 빌드 시스템
간의 강력한 결합에 대한 Apple의 입장은 시간이 지나도 Bazel 프로젝트를 유지하기 어렵게 만드는 또 다른 요인입니다.

> [!TIP] 튜이스트의 독창성은 그 섬세함에 있습니다 튜이스트는 Xcode 및 Xcode 프로젝트와 싸우는 대신 그것을 받아들입니다. 동일한
> 개념(예: 타겟, 스키마, 빌드 설정), 익숙한 언어(예: Swift), 간단하고 즐거운 경험으로 프로젝트를 유지 관리하고 확장하는 것이
> iOS 플랫폼 팀뿐만 아니라 모든 사람의 일이 될 수 있습니다.

## 규칙 {#규칙}

Bazel은 규칙을 사용하여 소프트웨어를 빌드하고 테스트하는 방법을 정의합니다. 이 규칙은 Python과 유사한 언어인
[Starlark](https://github.com/bazelbuild/starlark)로 작성됩니다. Tuist는 Swift를 구성 언어로
사용하므로 개발자는 Xcode의 자동 완성, 유형 검사 및 유효성 검사 기능을 편리하게 사용할 수 있습니다. 예를 들어, 다음 규칙은
Bazel에서 Swift 라이브러리를 빌드하는 방법을 설명합니다:

::: 코드 그룹
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

다음은 또 다른 예시이지만 Bazel과 Tuist에서 단위 테스트를 정의하는 방법을 비교한 것입니다:

:::코드 그룹
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
:::


## 스위프트 패키지 관리자 종속성 {#swift-package-manager-dependencies}

Bazel에서는
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[가젤](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 플러그인을
사용하여 Swift 패키지를 종속 요소로 사용할 수 있습니다. 이 플러그인에는 종속성에 대한 소스로 `Package.swift` 가 필요합니다.
그런 의미에서 튜이스트의 인터페이스는 바젤과 비슷합니다. ` tuist install` 명령을 사용하여 패키지의 종속성을 해결하고 가져올 수
있습니다. 해결이 완료되면 `tuist generate` 명령으로 프로젝트를 생성할 수 있습니다.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 프로젝트 생성 {#project-generation}

커뮤니티에서는 Bazel에서 선언한 프로젝트에서 Xcode 프로젝트를 생성하기 위한 규칙 집합인
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)을
제공합니다. ` BUILD` 파일에 일부 구성을 추가해야 하는 Bazel과 달리 Tuist는 구성이 전혀 필요하지 않습니다. 프로젝트의 루트
디렉터리에서 `tuist generate` 을 실행하면 Tuist가 Xcode 프로젝트를 생성합니다.
