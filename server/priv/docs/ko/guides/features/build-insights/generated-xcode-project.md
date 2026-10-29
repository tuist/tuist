---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 빌드 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Tuist가 생성한 Xcode 프로젝트의 빌드 분석 데이터를 추적합니다."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-build-insights}

> [!NOTE]
> 자동 생성된 스킴에는 `tuist inspect build` 포스트 액션이 자동으로 포함됩니다.

>
> 생성된 스킴에서 빌드 인사이트를 추적하지 않으려면 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)을 사용하여 비활성화하세요.

커스텀 스킴이 포함된 생성된 프로젝트를 사용하는 경우, 포스트 액션을 직접 추가해야 합니다. [Mise](https://mise.jdx.dev/)의 경우:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise를 사용하지 않는 경우, Xcode 포스트 액션이 셸의 `PATH`을 상속받지 않기 때문에 스킴 환경에서 `tuist`가 사용 가능하도록 해야 합니다. [Homebrew](https://brew.sh/) 설치의 경우:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## CI에서의 빌드 인사이트 {#continuous-integration}

CI에서 빌드 인사이트를 추적하려면 CI가 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link> 상태인지 확인하세요.

Xcodebuild 기반 CI의 경우 다음을 수행해야 합니다:
- `xcodebuild` 액션을 호출할 때 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>를 사용하세요.
- `xcodebuild` 명령에 `-resultBundlePath`를 추가하세요.

`-resultBundlePath`가 없으면 필요한 활동 로그와 결과 번들이 생성되지 않으며 `tuist inspect build`가 빌드를 분석할 수 없습니다.

## 머신 메트릭 {#machine-metrics}

빌드 인사이트에는 빌드 중에 캡처된 머신 수준의 성능 메트릭(CPU, 메모리, 네트워크 및 디스크 사용량)이 포함될 수 있습니다. 이를 활성화하려면 시스템 메트릭을 지속적으로 샘플링하는 경량 백그라운드 데몬을 설정하세요:

```bash
tuist setup insights
```

이는 백그라운드에서 메트릭을 샘플링하는 로컬 데몬을 실행합니다. 데이터는 `tuist inspect build`에 의해 자동으로 수집되어 빌드 보고서와 함께 업로드됩니다.

> [!TIP]
> **CI**
>
> 머신 메트릭을 캡처하려면 빌드 전에 CI 머신에서 `tuist setup insights`를 실행하세요.

머신 메트릭 수집을 중지하려면 다음을 실행하세요:

```bash
tuist teardown insights
```

이는 데몬의 LaunchAgent를 언로드하고 plist를 제거하며 `~/.local/state`에서 샘플링된 메트릭과 데몬 로그를 삭제하므로 백그라운드에서 실행되는 프로세스가 남지 않습니다.


## 커스텀 메타데이터 {#custom-metadata}

환경 변수를 사용하여 빌드에 메타데이터를 첨부하면 필터링을 개선할 수 있습니다.

### 환경 변수

| 변수 | 형식 | 설명 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 쉼표로 구분 | 하나의 변수에 여러 태그. |
| `TUIST_BUILD_VALUE_*` | 단일 값 | 접미사가 키인 키-값 쌍. |

### 예시

빌드를 호출하기 전에 CI 또는 셸에서 이러한 값을 설정하세요:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
