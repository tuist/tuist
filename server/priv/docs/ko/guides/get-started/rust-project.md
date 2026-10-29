---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
}
---
# Rust 프로젝트 {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 필수 조건

- Cargo로 빌드된 Rust 프로젝트.
- Tuist CLI와 Tuist 계정.

Tuist는 기존 Cargo 프로젝트와 함께 작동합니다. Rust 종속성을 추가하거나 프로젝트 빌드 방식을 변경할 필요가 없습니다.

## 프로젝트 연결

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>와 Rust를 설치하세요. 대시보드에서 빌드 시스템으로 **Cargo (Rust)** 를 선택하여 프로젝트를 생성하세요. 저장소 루트에 `tuist.toml`을 추가하세요:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

`tuist auth login`로 로그인한 후, 평소 사용하던 Cargo 명령어를 Tuist를 통해 실행하세요. CI 환경에서는 `TUIST_TOKEN`를 프로젝트 토큰으로 설정하세요. 구성 파일을 추가하는 대신 `TUIST_PROJECT`를 설정할 수 있으며, 자체 호스팅 서버를 사용하는 경우 `TUIST_URL`도 설정할 수 있습니다.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

기능, 툴체인, 테스트 필터 등 Cargo에 일반적으로 전달하는 것과 동일한 인수를 사용하세요. Tuist가 보고서를 업로드하지 못하더라도 Cargo는 기존 출력과 종료 코드를 유지합니다.

## Cargo 계속 입력하기

[mise의 명령어 래퍼](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers)를 활성화한 상태에서 이를 `mise.toml`에 추가하세요:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

래퍼를 추가한 후 `mise reshim`를 실행하세요. 이후에는 평소처럼 `cargo build`, `cargo check`, `cargo test`를 사용할 수 있습니다. Mise가 이를 Tuist를 통해 실행해 줍니다.

> [!TIP] Coding agents
> 코딩 에이전트와 작업할 때 유용합니다: 에이전트가 `tuist` 접두사를 추가하라는 알림 없이도 `cargo build` 및 `cargo test`를 계속 실행할 수 있습니다.

## 컴파일 캐시

`tuist cargo build`는 자격이 있는 레지스트리 리프 라이브러리를 로컬 및 Kura의 원격 캐시를 통해 자동으로 캐시합니다. 추가 도구나 캐시 구성이 필요하지 않습니다. 이 캐시는 실험적 기능이며 모든 컴파일을 포함하거나 다른 체크아웃 경로 간 재사용을 아직 지원하지 않습니다. 지원되는 컴파일, 인증 및 재사용 확인 방법은 <.localized_link href="/guides/features/cache/rust">Rust 캐시</.localized_link>를 참조하세요.

## 빌드 인사이트

대시보드에서 **Builds**를 열어 빌드 소요 시간을 확인하고 로컬 빌드와 CI를 비교하세요. 빌드를 선택하여 컴파일에 가장 오래 걸린 크레이트를 찾고 경고 및 오류를 검사하세요.

컴파일러 타이밍은 개별 소스 파일이 아닌 크레이트 기준입니다. 빌드 보고서 읽기에 대한 자세한 내용은 <.localized_link href="/guides/features/build-insights/rust">Rust 빌드 인사이트</.localized_link>를 참조하세요.

## 테스트 인사이트

평소대로 테스트를 실행하세요:

```sh
tuist cargo test --workspace
```

대시보드에서 **Tests**를 열어 통과, 실패, 무시된 테스트(독스트 포함)를 확인하세요. Cargo는 스위트 지속 시간을 보고하지만, 안정적인 libtest는 테스트별 타이밍을 노출하지 않습니다.

독스트만 실행하려면:

```sh
tuist cargo test --doc
```

자세한 내용은 <.localized_link href="/guides/features/test-insights/rust">Rust 테스트 인사이트</.localized_link> 및 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 불안정 테스트</.localized_link>를 참조하세요.
