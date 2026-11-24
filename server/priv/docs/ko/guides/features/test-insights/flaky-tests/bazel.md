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

Tuist는 Bazel의 `test.xml` 리포트에 포함된 개별 케이스를 사용하여 재시도 간, 그리고 지속적 통합(CI)에서 동일한 커밋과 타겟 선택으로 실행한 여러 빌드 간에 일관되지 않은 결과를 감지합니다. 로컬 실행 결과는 계속 표시되지만 테스트 케이스를 자동으로 불안정하다고 플래그 지정하지는 않습니다.

### 테스트 재시도 {#test-retries}

재시도는 선택 사항이며 격리(quarantine)와 독립적입니다. `--flaky_test_attempts=3`는 테스트당 최대 **Bazel 시도 횟수 3회**를 활성화하며, 추가 재시도 3회를 의미하지 않습니다. 기존 재시도 설정을 `.bazelrc`에 유지하거나 명시적으로 전달하세요:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Tuist가 결과를 관찰하려면 재시도가 실제로 실행되어야 합니다. Bazel 타겟의 불안정성 요약만으로는 어떤 개별 케이스가 불안정했는지 식별할 수 없습니다.

### 실행 간 비교 감지 {#cross-run-detection}

실행을 비교하려면 커밋 및 브랜치 메타데이터가 필요합니다. 빌드 환경이 이를 이미 제공하지 않는 경우 직접 제공하세요:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

케이스는 타겟 레이블, 클래스 이름(없으면 스위트 이름으로 대체), 그리고 테스트 이름으로 식별되며, 자세한 내용은 <.localized_link href="/guides/features/test-insights/bazel">Bazel 테스트 인사이트</.localized_link>를 참조하세요.

<!-- @snippet: ./_managing -->

## 불안정한 테스트 격리하기 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test`는 각 호출 전에 격리 정책을 가져와서 내부의 `bazel test` 실행에 적용합니다. 일반적인 `bazel test`는 여전히 테스트 결과를 보고하지만 격리는 적용하지 않습니다:

```sh
tuist bazel test -- //app:tests
```

`--` 이후의 인수는 `bazel test`로 전달됩니다. `--path`를 사용하여 프로젝트와 작업 디렉터리를 선택하고, `--bazel`를 사용하여 `bazelisk`와 같은 다른 실행 파일을 선택하세요. `--config=ci`와 같은 명명된 Bazel 구성은 선택 사항이며 동일하게 작동합니다.

### 음소거(Mute) {#mute}

기본 격리 워크플로로 **Mute**를 사용하세요. 음소거된 케이스는 계속 실행되며, 실패는 계속 표시되고 정상적인 sibling 케이스는 결과에 영향을 미칩니다. Tuist는 실패한 각 타겟의 모든 실패가 음소거된 케이스에 귀속될 때만 Bazel의 테스트 실패 종료 상태를 성공으로 변경합니다. 빌드 오류, 타임아웃, 중단된 실행, 누락되거나 불완전한 리포트, 그리고 음소거 집합 외부의 실패는 Bazel의 실패 상태를 유지합니다.

### 건너뛰기(Skip) {#skip}

건너뛰기는 Bazel 타겟 단위로 작동합니다. 하나의 케이스를 건너뛰면 해당 타겟 전체(정상적인 케이스 포함)가 제외되는데, 이는 Bazel이 모든 테스트 프레임워크에 대해 개별 케이스를 필터링할 수 없기 때문입니다. 전체 타겟을 제외하려는 경우가 아니라면 **Mute**를 선호하세요. 명령어는 제외된 모든 타겟 레이블을 출력하므로 빌드 로그에서 격리 정책에 의해 제외된 내용을 확인할 수 있습니다.

건너뛴 타겟이 더 이상 존재하지 않으면 Tuist는 경고에서 해당 타겟을 명시하고 그 제외 없이 실행합니다. 오래된 케이스를 **Enabled** 상태로 되돌려 정책을 영구적으로 제거하세요. 테스트 타겟이 하나도 남지 않으면 Bazel은 정상적인 "테스트를 찾을 수 없음" 종료 상태를 유지합니다.

<!-- @snippet: ./_quarantined-passing -->

### 격리된 테스트 다시 실행하기 {#running-quarantined-tests-again}

수정을 조사하거나 검증하려면 격리 정책을 우회하세요:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

케이스를 **Enabled** 상태로 되돌려 후속 일반 실행에 해당 타겟을 포함시키세요. 건너뛴 케이스는 명시적으로 포함될 때까지 새로운 실행을 생성하지 않으므로, 성공적인 새 실행을 기반으로 하는 자동화는 이를 복구하기 전에 검증 실행이 필요합니다.

### 제한 사항 {#limitations}

- 명시적인 `--build_event_json_file` 또는 `--target_pattern_file`는 활성 격리와 함께 사용할 수 없습니다. 타겟 패턴을 직접 전달하세요.
- Tuist가 격리 정책을 가져올 수 없는 경우, 명령어는 테스트 실행 전에 중지됩니다. 부분적인 정책은 절대 적용되지 않습니다. 의도적으로 격리 없이 실행하려면 `--no-quarantine`를 사용하세요.
- 이전 스위트 기반 식별자 아래에 기록된 음소거와 일치하는 실패는 차단 상태로 유지되며, 명령어는 다시 적용해야 할 정책을 명시합니다.

내부 동작에 대해서는 Bazel의 [테스트 필터](https://bazel.build/docs/user-manual#test-filter), [명령 옵션](https://bazel.build/reference/command-line-reference) 및 [빌드 이벤트 설명](https://bazel.build/remote/bep-glossary)을 참조하세요.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
