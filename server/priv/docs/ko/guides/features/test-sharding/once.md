---
{
  "title": "Once 테스트 샤딩",
  "titleTemplate": ":title · 테스트 샤딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist를 통해 Once 테스트 배치를 계획하고 CI 워커에 분산한 뒤 통합된 테스트 실행을 확인하세요."
}
---
# Once 테스트 샤딩 {#once-test-sharding}

테스트 스위트가 단일 머신으로 처리하기 어려울 정도로 커지면, Once는 Tuist에 발견된 테스트 배치를 CI 워커에 분배하도록 요청할 수 있습니다. 워커는 Once를 통해 할당된 작업을 실행하고, Tuist는 이들의 보고서를 하나의 테스트 실행으로 통합합니다.

> [!IMPORTANT]
> **요구 사항**
>
> - <.localized_link href="/guides/get-started/once-project">Once 시작하기</.localized_link>를 완료하세요.
> - `once query test-plan --shards` 및 `once test --shard-plan`를 노출하는 Once 릴리스를 사용하세요. Once 0.71.0은 이 호스팅 워크플로우가 아닌 포터블 플랜만 지원합니다.
> - 선택한 테스트 타겟에 대한 완전한 검색(discovery)을 수행하고, 워커에서 동일한 체크아웃 및 테스트 환경을 사용할 수 있도록 하세요.

Tuist CLI 래퍼가 필요하지 않습니다. Once는 네이티브 Tuist 제공자와 자격 증명을 사용합니다.

## 테스트 검색 {#discover-your-tests}

플래닝 전에 검색을 확립하기 위해 선택한 테스트를 실행하세요:

```bash
once test MyTests --format json
```

사용 가능한 배치 세분성은 러너에 따라 다릅니다. 일부 테스트 타겟은 파일 또는 케이스 배치를 지원하지만, 다른 타겟은 타겟 수준으로 유지됩니다. 검색 및 배치 기능에 대해서는 [Once의 테스트 가이드](https://buildonce.dev/docs/guide/graph/testing)를 따르세요.

## 호스팅 플랜 생성 {#create-a-hosted-plan}

플래닝 작업에서 이 CI 실행과 공유되는 참조를 사용하세요:

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

응답에는 호스팅 플랜 ID와 실제 워커 인덱스가 포함됩니다:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

네 개의 항목이 있다고 가정하지 말고 `shards`에서 CI 매트릭스를 구축하세요. 빈 플랜은 빈 ID와 배열을 반환하므로 워커를 시작할 필요가 없습니다. 플랜을 좁히려면 `--target`를 전달하거나, Once의 그래프 기반 선택을 사용하려면 `--changed-path`를 반복하세요.

참조는 기본적으로 `TUIST_SHARD_REFERENCE` 또는 감지된 CI 실행으로 설정됩니다. 환경에 지원되는 CI 식별자가 없는 경우 명시적으로 전달하세요.

## 각 샤드 실행 {#execute-each-shard}

모든 워커에 반환된 플랜 ID와 해당 인덱스를 제공하세요:

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

또는 `TUIST_SHARD_PLAN_ID` 및 `TUIST_SHARD_INDEX`를 설정하세요. 워커는 정확한 UUID로 바인딩된 플랜을 다운로드하고 할당된 배치만 실행합니다. 할당이 비어 있으면 아무 것도 실행되지 않으며, 결과 누락, 프로세스 실패 및 중단된 작업은 파티션을 통과할 수 없습니다.

이는 미리 컴파일된 테스트 빌드 아카이브가 아닌 테스트 플랜을 분배합니다. 워커에서 필요한 소스, 도구 및 검색을 준비하세요. 공유 캐싱을 사용하면 eligible한 빌드 작업을 반복하지 않을 수 있습니다.

## 재실행 및 결과 {#reruns-and-results}

재실행의 경우 `--shard-attempt`를 증가시키거나 `TUIST_SHARD_ATTEMPT`를 설정하세요. 그렇지 않으면 Once는 GitHub 실행 시도(attempt)를 사용하고, 기본값은 1입니다. `--shard-report-revision`의 기본값은 0이며, 동일한 시도 내에서 보고서를 수정할 때 증가시킬 수 있습니다. 이러한 카운터는 테스트 재시도와 별개입니다.

**Tests → Shards**를 열어 플랜, 균형 및 보고된 워커를 검사한 다음, 개별 결과를 확인하기 위해 결합된 테스트 실행을 엽니다. Once의 스케줄링 단위는 **Batches**로 표시되며; 케이스는 고유한 타겟, 스위트 및 테스트 이름을 유지합니다.

보고서 세부 정보 및 커버리지 제한 사항에 대해서는 <.localized_link href="/guides/features/test-insights/once">Once 테스트 인사이트</.localized_link>를 참조하세요.
