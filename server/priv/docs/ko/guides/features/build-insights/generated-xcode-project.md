---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 빌드 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Tuist가 생성한 Xcode 프로젝트의 빌드 분석 정보를 추적하세요."
}
---
# 생성된 Xcode 프로젝트 {#generated-xcode-project-build-insights}

> [!NOTE]
> 자동 생성된 스킴에는 `tuist inspect build` 포스트 액션이 자동으로 포함됩니다.
>
> 생성된 스킴에서 빌드 인사이트를 추적하지 않으려면 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)을 사용하여 비활성화하세요.

사용자 정의 스킴이 포함된 생성된 프로젝트를 사용하는 경우, 포스트 액션을 직접 추가해야 합니다. [Mise](https://mise.jdx.dev/)의 경우:

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

Mise를 사용하지 않는 경우, Xcode 포스트 액션이 셸의 `PATH`을 상속받지 않기 때문에 스킴 환경에서 `tuist`를 사용할 수 있도록 해야 합니다. [Homebrew](https://brew.sh/) 설치의 경우:

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

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
