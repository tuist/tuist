---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust 테스트 샤딩 {#rust-test-sharding}

Tuist는 일반 `cargo test` 실행을 샤딩하거나 컴파일된 테스트를 CI 워커에 분산하지 않습니다. shard-plan 환경 변수를 설정해도 Cargo가 실행하는 테스트는 변경되지 않습니다.

대신 단일 CI 작업에서 테스트를 실행하세요:

```sh
tuist cargo test --workspace
```

Cargo는 로컬 테스트 병렬 처리를 관리하며, Tuist는 doctest를 포함한 결과를 보고합니다. 설정 및 보고 세부 정보는 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>를 참조하세요.

Cargo의 패키지 선택 및 테스트 필터를 사용하여 각 작업이 실행할 내용을 선택할 수 있지만, 이러한 작업은 독립적인 실행이며 Tuist가 관리하는 샤드가 아닙니다.
