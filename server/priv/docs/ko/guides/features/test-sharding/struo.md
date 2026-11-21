---
{
  "title": "Struo 테스트 샤딩",
  "titleTemplate": ":title · 테스트 샤딩 · 기능 · 가이드 · Tuist",
  "description": "Tuist를 통해 Struo 테스트 배치를 계획하고, CI 워커에 분배하며, 통합된 테스트 실행을 검사합니다."
}
---
# Struo 테스트 샤딩 {#struo-test-sharding}

<a id="once-test-sharding"></a>

테스트 스위트가 단일 머신으로 처리하기 어려울 정도로 커지면, Struo는 Tuist에 발견된 테스트 배치를 CI 워커에 분배하도록 요청할 수 있습니다. 워커는 Struo를 통해 할당된 작업을 실행하고, Tuist는 각 보고서를 하나의 테스트 실행으로 결합합니다.

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo 시작하기</.localized_link>를 완료하세요.
> - [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 이상 버전을 사용하고, `struo query test-plan --shards` 및 `struo test --shard-plan` 옵션을 활용하세요.
> - 선택한 테스트 대상에 대한 완전한 탐색이 이루어져야 하며, 워커에서 동일한 체크아웃과 테스트 환경을 사용할 수 있어야 합니다.

Tuist CLI 래퍼는 필요하지 않습니다. Struo는 자체 Tuist 제공자와 자격 증명을 사용합니다.

## 테스트 탐색하기 {#discover-your-tests}

계획 수립 전에 선택한 테스트를 실행하여 탐색을 설정하세요:

```bash
struo test MyTests --format json
```

사용 가능한 배치 세분성은 러너에 따라 다릅니다. 일부 테스트 대상은 파일 또는 케이스 단위의 배치를 지원하지만, 다른 대상은 대상 수준으로 유지됩니다. 탐색 및 배치 기능에 대해서는 [Struo의 테스트 가이드](https://struo.run/docs/guide/graph/testing)를 참조하세요.

## 호스팅된 계획 생성하기 {#create-a-hosted-plan}

계획 작업에서는 이 CI 실행과 공유되는 참조 값을 사용하세요:

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

응답에는 호스팅된 계획 ID와 실제 워커 인덱스가 포함됩니다:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI 매트릭스를 `shards`에서 빌드하세요. 항목이 네 개라고 가정하지 마십시오. 빈 계획은 빈 ID와 배열을 반환하므로 워커를 시작할 필요가 없습니다. 계획을 좁히려면 `--target`를 전달하거나, Struo의 그래프 기반 선택을 사용하려면 `--changed-path`를 반복해서 전달하세요.

참조 값의 기본값은 `TUIST_SHARD_REFERENCE` 또는 감지된 CI 실행입니다. 환경에서 지원되는 CI 식별자가 없을 때는 명시적으로 전달하세요.

## 각 샤드 실행하기 {#execute-each-shard}

모든 워커에 반환된 계획 ID와 해당 인덱스를 제공하세요:

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

대안으로 `TUIST_SHARD_PLAN_ID` 및 `TUIST_SHARD_INDEX`를 설정하세요. 워커는 정확한 UUID로 바인딩된 계획을 다운로드하고 할당된 배치만 실행합니다. 할당이 비어 있으면 아무것도 실행되지 않으며, 결과 누락, 프로세스 실패, 작업 중단은 파티션을 통과할 수 없습니다.

이는 미리 컴파일된 테스트 빌드 아카이브가 아닌 테스트 계획을 분배하는 것입니다. 워커에서 필요한 소스, 도구 및 탐색을 준비하세요. 공유 캐싱을 사용하면eligible한 빌드 작업을 반복하지 않아도 됩니다.

## 재실행 및 결과 {#reruns-and-results}

재실행 시에는 `--shard-attempt`를 증가시키거나 `TUIST_SHARD_ATTEMPT`를 설정하세요. 그렇지 않으면 Struo는 GitHub 실행 시도 값을 사용하고, 기본값은 1입니다. `--shard-report-revision`의 기본값은 0이며, 동일한 시도 내에서 보고서를 수정할 때 증가시킬 수 있습니다. 이러한 카운터는 테스트 재시도와 별개입니다.

**Tests → Shards**를 열어 계획, 균형, 보고된 워커를 검사한 다음, 개별 결과를 확인하기 위해 결합된 테스트 실행을 엽니다. Struo의 스케줄링 단위는 **Batches**로 표시되며, 케이스는 고유의 대상, 스위트 및 테스트 이름을 유지합니다.

보고서 세부 정보 및 커버리지 제한 사항에 대해서는 <.localized_link href="/guides/features/test-insights/struo">Struo 테스트 인사이트</.localized_link>를 참조하세요.
