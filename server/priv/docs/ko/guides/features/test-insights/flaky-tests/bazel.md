---
{
  "title": "Bazel 불안정한 테스트",
  "titleTemplate": ":title · 불안정한 테스트 · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "불안정한 Bazel 테스트를 감지하고, 실패를 음소거하며, 격리된 타겟을 건너뜁니다."
}
---
# Bazel 불안정한 테스트 {#bazel-flaky-tests}

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Bazel 테스트 인사이트</.localized_link>가 `tuist bazel setup`를 통해 구성되었습니다.

<!-- @snippet: ./_intro -->

## 불안정성 감지 방식 {#how-it-works}

Tuist는 Bazel의 `test.xml` 리포트에서 개별 케이스를 사용하여 재시도 간, 그리고 지속적 통합(CI)에서 동일한 커밋과 타겟 선택에 대한 실행 간 일관되지 않은 결과를 감지합니다. 로컬 실행은 계속 표시되지만 테스트 케이스를 자동으로 불안정하다고 플래그 지정하지는 않습니다.

### 테스트 재시도 {#test-retries}

재시도는 선택 사항이며 격리와 독립적입니다. `--flaky_test_attempts=3`는 테스트당 **최대 세 번의 Bazel 시도**를 활성화하며, 추가 재시도 세 번을 의미하지 않습니다. 기존 재시도 설정을 `.bazelrc`에 유지하거나 명시적으로 전달하세요:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Tuist가 결과를 관찰하려면 재시도가 실제로 실행되어야 합니다. Bazel 타겟의 불안정성 요약만으로는 어떤 개별 케이스가 불안정했는지 식별할 수 없습니다.

### 실행 간 감지 {#cross-run-detection}

실행을 비교하려면 커밋 및 브랜치 메타데이터가 필요합니다. 빌드 환경에서 이미 공개하지 않는 경우 이를 제공하세요:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

케이스는 타겟 레이블, 클래스 이름(\_suite\_ 이름으로 대체), 테스트 이름으로 식별되며, 이는 <.localized_link href="/guides/features/test-insights/bazel">Bazel 테스트 인사이트</.localized_link>에 설명되어 있습니다.

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test`는 각 호출 전에 격리 정책을 가져와서 기본 `bazel test` 실행에 적용합니다. 일반 `bazel test`는 여전히 테스트 결과를 보고하지만 격리를 적용하지는 않습니다:

```sh
tuist bazel test -- //app:tests
```

`--` 이후의 인수는 `bazel test`로 전달됩니다. 프로젝트와 작업 디렉터리를 선택하려면 `--path`를 사용하고, `bazelisk`와 같은 다른 실행 파일을 선택하려면 `--bazel`를 사용하세요. `--config=ci`와 같은 명명된 Bazel 구성은 선택 사항이며 동일하게 작동합니다.

### 음소거 {#mute}

주요 격리 워크플로로 **음소거**를 사용하세요. 음소거된 케이스는 계속 실행되며, 실패는 계속 표시되고 정상인Sibling 케이스는 결과에 여전히 영향을 미칩니다. Tuist는 보고서가 실패한 각 타겟의 모든 실패를 음소거된 케이스에 귀속시킬 때만 Bazel의 테스트 실패 종료 상태를 성공으로 전환합니다. 빌드 오류, 시간 초과, 중단된 실행, 누락되거나 불완전한 리포트, 음소거 집합 외부의 실패는 Bazel의 실패 상태를 유지합니다.

### 스킵 {#skip}

스킵은 Bazel 타겟 단위로 작동합니다. 하나의 케이스를 스킵하면 해당 타겟 전체(정상 케이스 포함)가 제외됩니다. Bazel은 모든 테스트 프레임워크에 대해 개별 케이스를 필터링할 수 없기 때문입니다. 전체 타겟을 제외하려는 경우가 아니라면 **음소거**를 선호하세요. 명령어는 제외된 모든 타겟 레이블을 출력하므로 빌드 로그에 격리 정책이 무엇을 제외했는지 표시됩니다.

스킵된 타겟이 더 이상 존재하지 않는 경우, Tuist는 경고에서 이를 명시하고 해당 제외 없이 실행합니다. 오래된 케이스를 **활성화됨**으로 반환하여 정책을 영구적으로 제거하세요. 테스트 타겟이 남아 있지 않으면 Bazel은 정상적인 "테스트를 찾을 수 없음" 종료 상태를 유지합니다.

<!-- @snippet: ./_quarantined-passing -->

### 격리된 테스트 다시 실행 {#running-quarantined-tests-again}

수정을 조사하거나 검증하려면 격리 정책을 우회하세요:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

케이스를 **활성화됨**으로 반환하여 후속 일반 실행에 타겟을 포함시키세요. 스킵된 케이스는 명시적으로 포함될 때까지 새로운 실행을 생성하지 않으므로, 성공적인 새 실행을 기반으로 하는 자동화는 이를 복구하기 전에 검증 실행이 필요합니다.

### 제한 사항 {#limitations}

- 명시적인 `--build_event_json_file` 또는 `--target_pattern_file`는 활성 격리와 결합할 수 없습니다. 타겟 패턴을 직접 전달하세요.
- Tuist가 격리 정책을 가져올 수 없는 경우, 명령어는 테스트 실행 전에 중지됩니다. 부분적인 정책을 적용하지 않습니다. 의도적으로 격리 없이 실행하려면 `--no-quarantine`를 사용하세요.
- 이전 suite 기반 신원 아래 기록된 음소거와 일치하는 실패는 차단 상태로 유지되며, 명령어는 재적용할 정책을 명시합니다.

기본 동작에 대해서는 Bazel의 [테스트 필터](https://bazel.build/docs/user-manual#test-filter), [명령 옵션](https://bazel.build/reference/command-line-reference) 및 [빌드 이벤트 설명](https://bazel.build/remote/bep-glossary)을 참조하세요.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
