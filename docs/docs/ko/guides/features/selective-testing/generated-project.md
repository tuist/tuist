---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# Generated 프로젝트 {#generated-projects}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

생성된 프로젝트에서 선택적으로 테스트를 실행하려면 `tuist test` 명령을 사용합니다. 이 명령은
<LocalizedLink href="/guides/features/cache#cache-warming">캐시 워밍업</LocalizedLink>과 동일한 방식으로 Xcode 프로젝트를
<LocalizedLink href="/guides/features/projects/hashing">해시</LocalizedLink>하고,
성공하면 향후 실행에서 변경된 내용을 확인하기 위해 해시를 유지합니다.

향후 실행에서 `tuist test` 해시를 투명하게 사용하여 테스트를 필터링하여 마지막 테스트 실행 성공 이후 변경된 테스트만 실행합니다.

예를 들어 다음과 같은 종속성 그래프가 있다고 가정해 보겠습니다:

- `FeatureA` 에는 `FeatureATests` 테스트가 있으며, `Core에 의존합니다.`
- `FeatureB` 에는 `FeatureBTests` 테스트가 있으며, `Core에 의존합니다.`
- `코어` 테스트 있음 `코어테스트`

`튜이스트 테스트` 는 이와 같이 작동합니다:

| 액션            | 설명                                                          | 내부 상태                                                       |
| ------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| `튜이스트 테스트` 호출 | `CoreTests`, `FeatureATests`, `FeatureBTests에서 테스트를 실행합니다.` | `FeatureATests`, `FeatureBTests`, `CoreTests` 의 해시는 유지됩니다.  |
| `기능` 업데이트됨    | 개발자가 대상의 코드를 수정합니다.                                         | 이전과 동일                                                      |
| `튜이스트 테스트` 호출 | 해시가 변경되었으므로 `FeatureATests` 에서 테스트를 실행합니다.                  | `FeatureATests` 의 새 해시가 유지됩니다.                              |
| `핵심` 업데이트됨    | 개발자가 대상의 코드를 수정합니다.                                         | 이전과 동일                                                      |
| `튜이스트 테스트` 호출 | `CoreTests`, `FeatureATests`, `FeatureBTests에서 테스트를 실행합니다.` | `FeatureATests` `FeatureBTests`, `CoreTests` 의 새 해시는 유지됩니다. |

`튜이스트 테스트` 바이너리 캐싱과 직접 통합하여 로컬 또는 원격 저장소의 바이너리를 최대한 많이 사용하여 테스트 스위트를 실행할 때 빌드
시간을 개선할 수 있습니다. 선택적 테스트와 바이너리 캐싱을 결합하면 CI에서 테스트를 실행하는 데 걸리는 시간을 크게 줄일 수 있습니다.

## UI 테스트 {#ui-tests}

Tuist는 UI 테스트의 선택적 테스트를 지원합니다. 그러나 Tuist는 미리 대상을 알고 있어야 합니다. ` 대상` 매개 변수를 지정한
경우에만 Tuist는 다음과 같이 선택적으로 UI 테스트를 실행합니다:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
