---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcode 프로젝트 {#xcode-project}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

명령줄을 통해 Xcode 프로젝트의 테스트를 선택적으로 실행할 수 있습니다. 이를 위해 `xcodebuild` 명령 앞에 `tuist` 를
추가할 수 있습니다(예: `tuist xcodebuild test -scheme App`). 이 명령은 프로젝트를 해시하고 성공하면 해시를
유지하여 향후 실행에서 변경된 내용을 확인합니다.

향후 실행에서 `tuist xcodebuild test` 해시를 투명하게 사용하여 테스트를 필터링하여 마지막 테스트 실행 성공 이후 변경된
테스트만 실행합니다.

예를 들어 다음과 같은 종속성 그래프가 있다고 가정해 보겠습니다:

- `FeatureA` 에는 `FeatureATests` 테스트가 있으며, `Core에 의존합니다.`
- `FeatureB` 에는 `FeatureBTests` 테스트가 있으며, `Core에 의존합니다.`
- `코어` 테스트 있음 `코어테스트`

`튜이스트 X코드 빌드 테스트` 는 이와 같이 작동합니다:

| 액션                    | 설명                                                          | 내부 상태                                                       |
| --------------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| `튜이스트 엑스코드 빌드 테스트` 호출 | `CoreTests`, `FeatureATests`, `FeatureBTests에서 테스트를 실행합니다.` | `FeatureATests`, `FeatureBTests`, `CoreTests` 의 해시는 유지됩니다.  |
| `기능` 업데이트됨            | 개발자가 대상의 코드를 수정합니다.                                         | 이전과 동일                                                      |
| `튜이스트 엑스코드 빌드 테스트` 호출 | 해시가 변경되었으므로 `FeatureATests` 에서 테스트를 실행합니다.                  | `FeatureATests` 의 새 해시가 유지됩니다.                              |
| `핵심` 업데이트됨            | 개발자가 대상의 코드를 수정합니다.                                         | 이전과 동일                                                      |
| `튜이스트 엑스코드 빌드 테스트` 호출 | `CoreTests`, `FeatureATests`, `FeatureBTests에서 테스트를 실행합니다.` | `FeatureATests` `FeatureBTests`, `CoreTests` 의 새 해시는 유지됩니다. |

CI에서 `tuist xcodebuild test` 를 사용하려면
<LocalizedLink href="/guides/integrations/continuous-integration">연속 통합 가이드</LocalizedLink>의 지침을 따르세요.

다음 동영상을 통해 선택적 테스트가 실제로 작동하는 모습을 확인하세요:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
