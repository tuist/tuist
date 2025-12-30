---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazel 프로젝트 전환 {#migrate-a-bazel-project}

[Bazel](https://bazel.build)는 구글이 2015에 오픈 소스화 한 빌드 시스템 인데, 어떤 규모의 소프트웨어도 빠르고
신뢰성 있게 만들고 테스트할 수 있게 하는 강력한 도구 입니다.
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
나 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 같은 몇몇 큰 회사들이 사용하지만 도입과
유지 보수를 하려면 학습과 지속적인 투자를 필요로 합니다. 여러 분야를 다루는 몇몇 회사에는 맞지만, 제품 개발에 집중하는 다른 회사들에는 맞지
않을 수도 있습니다. 예를 들어, 우리가 본 iOS 플랫폼 팀을 소유한 회사들은 Bazel을 도입한 후 기술자들을 떠나게 만들었습니다.
Apple이 Xcode와 빌드 시스템 간에 강력한 결합을 고수하는 것은 Bazel 프로젝트를 유지 보수하기 어렵게 만드는 또 다른 요인 입니다.

::: tip TUIST의 특별함은 세련미에 있습니다
<!-- -->
Tuist는 Xcode와 Xcode 프로젝트에 대항하는 대신, 그것을 받아들입니다. 동일한 개념들(예, target, scheme, build
settings), 친숙한 언어 (예, Swift) 그리고 간결함과 iOS 플랫폼 팀들 뿐만 아니라 프로젝트를 유지 보수하고 확장하는 모든
직업들이 즐길 수 있는 경험 등을.
<!-- -->
:::

## 규칙 {#rules}

Bazel은 어떻게 소프트웨어를 만들고 테스트 할 지에 대한 규칙을 사용합니다. 이 규칙들은 Python 같은 언어 인
[Starlark](https://github.com/bazelbuild/starlark) 로 작업됩니다Tuist 는 Swift를 환경 설정
언어로 사용해서 개발자들에게 Xcode의 자동 완성, Type 확인, 유효성 검사 등의 편의성을 제공합니다. 예를 들어, 아래 규칙은
Bazel에서 어떻게 Swift 라이브러리를 생성 할 지를 설명합니다:

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

여기 다른 예제가 있지만 단위 테스트를 Bazel과 Tuist에서 어떻게 정의하는 지에 대한 비교 입니다.

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

Bazel에서, 여러분은 Swift Package들을 의존성으로 사용하게 위해
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
플러그인을 사용할 수 있습니다. 이 플러그인은 의존성의 출처로 `Package.swift` 를 요구 합니다. Tuist의 인터페이스도
Bazel과 유사하게 의존성 패키지들을 가져오기 위해 `tuist install` 명령을 사용할 수 있습니다. 가져 온 후에, 여러분은
프로젝트를 `tuist generate` 명령으로 행성 할 수 있습니다.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 프로젝트 생성 {#project-generation}

커뮤니티는 Xcode 프로젝트들을 Bazel로 선언된 프로젝트들로 만들기 위해 몇 가지 규칙 묶음인
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)을
제공합니다. `BUILD` 을 설정해야 하는 Bazel과는 달리, Tuist는 어떤 환경 설정도 전혀 필요하지 않습니다. 여러분은 최상위
경로에서 `tuist generate` 를 실행 할 수 있고, Tuist는 Xcode 프로젝트를 만들어 줄 것 입니다.
