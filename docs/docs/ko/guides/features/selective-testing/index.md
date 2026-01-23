---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# 선택적 테스트 {#selective-testing}

::: warning 요구 사항
<!-- -->
- <LocalizedLink href="/guides/features/projects"> 생성된 프로젝트</LocalizedLink>
- 1}Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

`생성된 프로젝트에서 선택적으로 테스트를 실행하려면 `tuist test` ` 명령을 사용하세요. 이 명령은
<LocalizedLink href="/guides/features/projects/hashing">해시값</LocalizedLink>을
생성하여 <LocalizedLink href="/guides/features/cache#cache-warming">캐시
예열</LocalizedLink>과 동일한 방식으로 Xcode 프로젝트를 처리하며, 성공 시 향후 실행에서 변경된 부분을 판단하기 위해 해시값을
저장합니다.

향후 실행 시 `tuist test` 은 해시(hash)를 투명하게 활용하여 테스트를 필터링하여, 마지막 성공적인 테스트 실행 이후 변경된
테스트만 실행합니다.

예를 들어, 다음과 같은 종속성 그래프를 가정합니다:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` has tests `FeatureBTests`, and depends on `Core`
- `Core` 에는 테스트가 있습니다 `CoreTests`

`tuist test` 는 다음과 같이 동작합니다:

| 액션                     | 설명                                                                    | 내부 상태                                                                      |
| ---------------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `tuist 테스트` 호출         | `의 CoreTests(`), `의 FeatureATests(`), `의 FeatureBTests에서 테스트를 실행합니다.` | `의 FeatureATests(`), `의 FeatureBTests(` ), `의 CoreTests(` ) 해시값은 영구 저장됩니다. |
| `FeatureA` 이 업데이트되었습니다 | 개발자는 대상의 코드를 수정합니다.                                                   | 이전과 동일                                                                     |
| `tuist 테스트` 호출         | `에서 FeatureATests 테스트 실행 중` 해시 변경으로 인해                                | `FeatureATests의 새 해시` 이 저장됩니다.                                             |
| `Core` 업데이트됨           | 개발자는 대상의 코드를 수정합니다.                                                   | 이전과 동일                                                                     |
| `tuist 테스트` 호출         | `의 CoreTests(`), `의 FeatureATests(`), `의 FeatureBTests에서 테스트를 실행합니다.` | `의 새 해시 FeatureATests` `FeatureBTests`, 그리고 `CoreTests` 가 지속됩니다.           |

`tuist 테스트` 는 바이너리 캐싱과 직접 연동되어 로컬 또는 원격 저장소의 바이너리를 최대한 활용하여 테스트 스위트 실행 시 빌드 시간을
단축합니다. 선택적 테스트와 바이너리 캐싱의 결합은 CI 환경에서 테스트 실행 시간을 획기적으로 줄일 수 있습니다.

## UI 테스트 {#ui-tests}

Tuist는 UI 테스트의 선택적 실행을 지원합니다. 다만 Tuist는 실행 대상을 사전에 알아야 합니다. `대상 지정` 매개변수를 명시해야만
Tuist가 다음과 같이 UI 테스트를 선택적으로 실행합니다:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
