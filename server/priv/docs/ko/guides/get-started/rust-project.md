---
{
  "title": "Rust 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "Rust 프로젝트를 Tuist에 연결하여 문서 테스트를 포함한 빌드와 테스트를 추적하고, 불안정한 테스트를 찾아보세요."
}
---
# Rust 프로젝트 {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 사전 요구 사항

- Cargo로 빌드되는 Rust 프로젝트.
- Tuist CLI와 Tuist 계정.

Tuist는 기존 Cargo 프로젝트와 함께 작동합니다. Rust 의존성을 추가하거나 프로젝트 빌드 방식을 변경할 필요가 없습니다.

## 프로젝트 연결

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>와 Rust를 설치하세요. 대시보드에서 빌드 시스템으로 **Cargo (Rust)** 를 선택하여 프로젝트를 생성하세요. 그런 다음 워크스페이스 루트의 `Cargo.toml`에 프로젝트를 추가하세요:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo는 `metadata` 테이블을 무시하므로 프로젝트 빌드 방식이 변경되지 않습니다. `[workspace]` 테이블이 없는 단일 크레이트의 경우 대신 `[package.metadata.tuist]`를 사용하세요. 이 테이블은 `tuist.toml` 파일과 동일한 설정을 허용하며, 저장소에 다른 빌드 시스템을 위한 프로젝트도 있는 경우 대신 사용할 수 있습니다. 둘 다 존재하는 경우 `tuist.toml`가 우선합니다.

`tuist auth login`로 로그인한 후 평소 사용하는 Cargo 명령어를 Tuist를 통해 실행하세요. CI 환경에서는 CI 제공자의 OIDC 신원으로 인증하거나 `TUIST_TOKEN`를 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>으로 설정하세요. 구성 파일을 추가하는 대신 `TUIST_PROJECT`를 설정할 수 있으며, 자체 호스팅 서버를 사용하는 경우 `TUIST_URL`도 설정할 수 있습니다.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

기능, 툴체인, 테스트 필터 등 평소 Cargo에 전달하는 것과 동일한 인수를 사용하세요. Tuist가 보고서를 업로드하지 못하더라도 Cargo는 평소와 동일한 출력 및 종료 코드를 유지합니다.

## Cargo 입력 계속하기

[mise의 명령어 래퍼](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers)를 활성화한 상태에서 이를 `mise.toml`에 추가하세요:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

래퍼를 추가한 후 `mise reshim`를 실행하세요. 이제 평소처럼 `cargo build`, `cargo check`, `cargo test`를 사용할 수 있습니다. Mise가 이를 Tuist를 통해 실행해 줍니다.

> [!TIP] Coding agents
> 코딩 에이전트와 작업할 때 유용합니다. `tuist` 접두사를 추가하도록 알림받지 않고도 `cargo build`와 `cargo test`를 계속 실행할 수 있습니다.

## 컴파일 캐시

`tuist cargo build`는 자격이 있는 컴파일, 의존성 및 빌드 스크립트 실행을 로컬 및 Kura의 원격 캐시를 통해 자동으로 캐시합니다. 추가 도구 또는 캐시 구성이 필요하지 않습니다. 이 캐시는 실험적 기능이며 Apple silicon Mac에서 검증되었으며 아직 모든 컴파일을 지원하지 않습니다. 지원되는 컴파일, 인증 및 재사용 확인 방법은 <.localized_link href="/guides/features/cache/rust">Rust 캐시</.localized_link>를 참조하세요.

## 빌드 인사이트

대시보드에서 **빌드**를 열어 빌드 소요 시간을 확인하고 로컬 빌드를 CI와 비교하세요. 빌드를 선택하여 컴파일에 가장 오래 걸린 크레이트를 찾고 경고 및 오류를 검사하세요.

컴파일러 타이밍은 개별 소스 파일이 아닌 크레이트 기준입니다. 빌드 보고서 읽기에 대한 자세한 내용은 <.localized_link href="/guides/features/build-insights/rust">Rust 빌드 인사이트</.localized_link>를 참조하세요.

## 테스트 인사이트

평소대로 테스트를 실행하세요:

```sh
tuist cargo test --workspace
```

대시보드에서 **테스트**를 열어 통과, 실패 및 무시된 테스트(독스트 포함)를 확인하세요. Cargo는 스위트 지속 시간을 보고하지만 안정된 libtest는 테스트별 타이밍을 노출하지 않습니다.

독스트만 실행하려면:

```sh
tuist cargo test --doc
```

자세한 내용은 <.localized_link href="/guides/features/test-insights/rust">Rust 테스트 인사이트</.localized_link> 및 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 불안정한 테스트</.localized_link>를 참조하세요.

## 상표 {#trademarks}

Rust와 Cargo는 Rust Foundation의 상표입니다. Tuist는 Rust Project 또는 Rust Foundation과 제휴하거나 승인을 받지 않았습니다. 이 가이드에 표시된 Rust 로고는 © Rust Foundation이며, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 라이선스에 따라 사용되고 페이지 테마에 맞는 단색으로 표시됩니다.
