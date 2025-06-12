---
title: Insights
titleTemplate: :title · Develop · Guides · Tuist
description: 개발 환경을 유지하기 위해 프로젝트에 대한 인사이트를 얻으세요.
---

# Insights {#insights}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

대규모 프로젝트 작업이 부담스럽게 느껴지면 안됩니다. 사실, 2주 전에 시작한 프로젝트처럼 즐거워야 합니다. 그렇지 못한 이유 중에 하나는 프로젝트가 커짐에 따라 개발자 경험이 나빠지기 때문입니다. 빌드 시간이 길어지고 테스트가 느리고 불안정해집니다. 이러한 문제들은 심각해질 때까지 무시되곤 하지만 그 시점이 되면 해결하기가 어렵습니다. Tuist Insights는 프로젝트의 상태를 모니터링하고, 프로젝트가 커져도 생산적인 개발 환경을 유지할 수 있도록 도와주는 툴을 제공합니다.

다시 말해, Tuist Insights는 다음과 같은 질문에 답을 얻을 수 있게 도와줍니다:

- 지난주에 빌드 시간이 크게 증가했나요?
- 테스트가 더 느려졌나요? 어떤 테스트가 그런가요?

> [!NOTE]\
> Tuist Insights는 아직 개발 단계입니다.

## 빌드 {#builds}

CI 워크플로우의 성능에 대한 지표는 가지고 있을 수 있지만, 로컬 개발 환경에 대한 내용은 부족할 수 있습니다. 그러나 빌드 시간은 개발자 경험에 대한 중요한 요소 중 하나입니다.

로컬 빌드 시간을 추적하려면 `tuist inspect build` 명령어를 스킴의 후속 작업으로 추가하여 활용할 수 있습니다:

![빌드 검사용 후속 작업](/images/guides/develop/insights/inspect-build-scheme-post-action.png)

[Mise](https://mise.jdx.dev/)를 사용하는 경우에, 후속 작업 환경에 `tuist`를 활성화하도록 스크립트를 설정해야 합니다:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

tuist inspect build
```

이제 Tuist 계정에 로그인된 상태에서는 로컬 빌드가 추적됩니다. 이제 Tuist 대시보드에서 빌드 시간을 확인하고 시간이 지남에 따라 어떻게 변하는지 살펴볼 수 있습니다:

> [!TIP]\
> 대시보드에 빠르게 접근하려면, CLI에서 `tuist project show-web` 명령어를 수행하세요.

![빌드 인사이트 대시보드](/images/guides/develop/insights/builds-dashboard.png)

## Projects {#projects}

> [!NOTE]\
> 자동 생성된 스킴에는 `tuist inspect build` 후속 작업이 자동으로 포함됩니다.
>
> 자동 생성된 스킴에서 빌드 인사이트 추적이 필요하지 않으면, <LocalizedLink href="references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink> 생성 옵션을 사용하여 비활성화할 수 있습니다.

생성된 프로젝트를 사용하면, 다음과 같이 커스텀 스킴을 사용하여 커스텀 <0>빌드 후속 작업</0>을 설정할 수 있습니다:

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
                        name: "Inspect Build",
                        scriptText: """
                        eval \"$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)\"
                        tuist inspect build
                        """
                    )
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .testAction(targets: ["MyAppTests"]),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise를 사용하지 않는다면, 스크립트를 다음과 같이 간단하게 작업할 수 있습니다:

```swift
.postAction(
    name: "Inspect Build",
    script: "tuist inspect build",
    execution: .always
)
```

## Continuous integration {#continuous-integration}

CI에서 빌드 시간을 추적하려면, CI가 <LocalizedLink href="/guides/automate/continuous-integration#authentication">인증</LocalizedLink>되었는지 확인해야 합니다.

추가로, 다음의 내용도 필요합니다:

- `xcodebuild` 작업을 실행할 때는 <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> 명령어를 사용합니다.
- `xcodebuild` 실행 시에 `-resultBundlePath`를 추가합니다.

`-resultBundlePath`없이 `xcodebuild`로 빌드를 수행하면, `.xcactivitylog` 파일이 생성되지 않습니다. 하지만 `tuist inspect build` 후속 작업은 빌드를 분석하기 위해 해당 파일이 생성되어야 합니다.
