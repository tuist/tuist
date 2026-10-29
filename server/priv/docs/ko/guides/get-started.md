---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# 시작하기 {#get-started}

현재 앱이 빌드되는 방식에 맞는 경로를 선택하세요. 각 경로는 설치 항목, 캐싱 및 인사이트와 테스트 기능 활성화 방법, 그리고 종단 간 설정 검증 방법을 안내합니다. 각 기능을 독립적으로 도입하거나, 여러 플랫폼에 배포하는 경우 결합하여 사용할 수 있습니다.

## Xcode 프로젝트 {#existing-xcode-project}

기존 Xcode 프로젝트나 워크스페이스를 유지하면서 Tuist 기능을 하나씩 추가하세요. 프로젝트 생성이 필요하지 않습니다.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 생성된 Xcode 프로젝트 {#generated-xcode-project}

Swift 매니페스트로부터 Tuist가 Xcode 프로젝트를 정의하고 생성하도록 하세요. 생성된 프로젝트는 모듈식 Xcode 프로젝트의 복잡성을 그래프의 간결하고 선언적인 설명으로 압축하며, <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link> 및 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">선택적 테스트</.localized_link>를 위한 필수 조건입니다.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 프로젝트 {#gradle-project}

`dev.tuist` Gradle 플러그인을 통해 Gradle 프로젝트를 Tuist의 원격 캐시, 빌드 인사이트 및 테스트 인사이트에 연결하세요.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 프로젝트 {#elixir-project}

`tuist_ex` Hex 패키지를 통해 Elixir 프로젝트를 Tuist의 빌드 인사이트, 테스트 인사이트, 불안정한 테스트 감지 및 테스트 샤딩에 연결하세요.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 프로젝트 {#rust-project}

Tuist CLI를 통해 Cargo를 실행하여 doc 테스트를 포함한 빌드 및 개별 테스트 결과를 보고하고 불안정한 테스트를 조사하세요.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 프로젝트 {#bazel-project}

Bazel 워크스페이스를 Tuist의 Remote Execution API 캐시 및 Build Event Service로 지정하여 팀과 CI 전반에서 캐시 히트와 인사이트를 공유하세요.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

이 중 어느 것을 시작하기 전에, <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스를 설치</.localized_link>하세요. Elixir 프로젝트는 예외입니다: Hex 패키지만이 필요합니다.
