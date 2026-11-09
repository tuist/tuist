---
{
  "title": "Bazel 테스트 인사이트",
  "titleTemplate": ":title · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Bazel 테스트 분석을 추적하여 테스트 성능과 안정성을 모니터링하세요."
}
---
# Bazel 테스트 인사이트 {#bazel-test-insights}

> [!IMPORTANT]
> **필수 조건**
>
> - `tuist bazel setup`을 통해 연결된 Bazel 워크스페이스(자세한 내용은 <.localized_link href="/guides/get-started/bazel-project">Bazel 프로젝트 시작하기</.localized_link> 참조).

`tuist bazel setup`는 `.bazelrc.tuist`에서 케이스별 보고를 구성하므로, 일반적인 `bazel test`는 다른 모든 빌드 시스템이 사용하는 동일한 대시보드에 개별 테스트 케이스를 보고합니다:

```bash
bazel test //app:tests
```

<.localized_link href="/guides/features/test-insights/flaky-tests/bazel">격리</.localized_link>도 적용하려면 대신 Tuist 래퍼를 통해 테스트를 실행하세요. `--` 뒤의 인수는 `bazel test`로 전달됩니다:

```bash
tuist bazel test -- //app:tests
```

## 추적 대상 {#what-is-tracked}

Tuist는 `test.xml` 보고서를 파싱하고 Bazel이 각 테스트 타겟에 대해 생성하는 `test.log` 출력을 캡처한 다음, 이를 공유 테스트 실행 모델로 집계합니다. 각 실행은 다음을 기록합니다:

- 개별 테스트 케이스의 통과, 실패 및 건너뜀 상태와 소요 시간.
- 테스트 타겟, 클래스 및 스위트 구조.
- Bazel이 불안정한 테스트를 재시도하도록 구성된 경우 재시도 시도 횟수.
- 타겟의 `test.log`에서 캡처된 실패 출력.

**테스트 실행**, **테스트 케이스** 및 개별 테스트 페이지는 모두 Bazel에서도 다른 빌드 시스템과 동일하게 작동합니다.

## 케이스별 JUnit 보고서 생성 {#per-case-junit-reports}

케이스별 행은 테스트 타겟이 Bazel이 제공하는 `$XML_OUTPUT_FILE` 경로에 JUnit `test.xml`을 작성하는지에 따라 달라집니다. 러너가 이를 작성하지 않으면 Bazel은 타겟 이름으로 합성된 단일 케이스 보고서로 대체하며, Tuist는 타겟당 하나의 행(**Bazel 타겟**으로 라벨링됨)을 표시하고 원본 `test.log`는 여전히 실행 페이지에서 확인할 수 있습니다.

대부분의 Bazel 테스트 규칙은 이미 실제 `test.xml`을 생성합니다:

- `java_test` 및 `kt_jvm_test`: JUnit이 내장되어 있습니다.
- GoogleTest를 사용한 `cc_test`: 최신 gtest에 대해 컴파일하면 러너가 JUnit을 작성합니다. 이전 설정에서는 `--gtest_output=xml:$XML_OUTPUT_FILE`가 필요합니다.
- `py_test`: `--junitxml=$XML_OUTPUT_FILE`와 함께 pytest를 사용하거나 `rules_python` pytest 러너를 사용합니다.
- `go_test`: `go test -json`를 `gotestsum --junitfile=$XML_OUTPUT_FILE`로 파이프하거나 JUnit을 생성하는 헬퍼로 감싸세요.

`rules_rust` 및 `rules_rs`의 `rust_test`는 표준 `libtest` 하네스를 실행하며, 이는 안정版 Rust에서 JUnit을 작성하지 않습니다. `libtest` 출력을 파싱하고 JUnit을 `$XML_OUTPUT_FILE`에 작성하는 스크립트로 테스트 타겟을 감싸면 Tuist에서 케이스별 행을 유지하면서도 동일한 실행이 단일 Bazel 테스트 타겟으로 남습니다.

## 테스트 식별자 {#test-identity}

케이스는 타겟 레이블, 클래스 이름(슈트 이름으로 대체) 및 테스트 이름으로 식별됩니다. 이로 인해 서로 다른 클래스에서 동일한 이름의 메서드가 분리됩니다. 다른 상위 스위트 이름을 사용한 이전 보고서는 기존 식별자 아래에서 이력을 유지합니다. 기존 식별자에 적용된 상태 변경 사항은 새 식별자에 다시 적용해야 하며, 명령은 실패가 기존 식별자와 일치할 때 경고하여 어떤 정책을 이동해야 할지 알려줍니다.

## CI 컨텍스트 제공 {#providing-ci-context}

Tuist는 Bazel의 빌드 메타데이터에서 git 커밋 및 브랜치 정보를 읽어 동일한 커밋에서의 실행을 환경 간에 비교할 수 있도록 합니다. 대부분의 지속적 통합 시스템은 이를 이미 설정하지만, 그렇지 않은 경우 명시적으로 전달하세요:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

동일한 `--build_metadata` 플래그는 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 빌드 인사이트</.localized_link> 페이지에서 호출 태깅을 위해 설명하는 것이므로, 단일 플래그 세트로 두 표면 모두를 커버합니다.

## 불안정한 테스트 및 격리 {#flaky-tests-and-quarantine}

재시도, 실행 간 불안정성 감지 및 케이스별 격리(음소거 및 건너뛰기)는 모두 `tuist bazel test`를 통해 작동합니다. 전체 워크플로는 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 불안정한 테스트</.localized_link>를 참조하세요.

## 데이터 보존 {#data-retention}

Tuist는 테스트 실행을 생성한 Bazel 호출, 해당 로그 및 대기 중인 테스트 수집 기록을 90일 동안 보관합니다. 테스트 케이스와 해당 실행 이력은 다른 모든 빌드 시스템과 동일한 모델을 사용하며 해당 기간의 적용을 받지 않습니다. 전체 정책은 <.localized_link href="/guides/server/data-retention">데이터 보존</.localized_link>을 참조하세요.
