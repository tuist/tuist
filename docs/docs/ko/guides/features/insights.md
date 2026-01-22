---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# 분석 생성 {#build-insights}

::: warning 요구 사항
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및
  프로젝트</LocalizedLink>
<!-- -->
:::

대규모 프로젝트 작업이 번거로운 일처럼 느껴져서는 안 됩니다. 오히려 불과 2주 전에 시작한 프로젝트에서 일하는 것처럼 즐거워야 합니다. 그렇지
않은 이유 중 하나는 프로젝트가 커질수록 개발자 환경이 악화되기 때문입니다. 빌드 시간이 길어지고 테스트가 느리고 불안정해집니다. 이러한 문제가
견딜 수 없는 지경에 이를 때까지 간과하기 쉽지만, 그 시점에서는 문제를 해결하기가 어렵습니다. 튜이스트 인사이트는 프로젝트의 상태를
모니터링하고 프로젝트 확장에 따라 생산적인 개발자 환경을 유지할 수 있는 도구를 제공합니다.

즉, 튜이스트 인사이트는 다음과 같은 질문에 답할 수 있도록 도와줍니다:
- 지난 주에 빌드 시간이 크게 증가했나요?
- 로컬 개발에 비해 CI에서 빌드 속도가 느려지나요?

CI 워크플로우의 성능에 대한 몇 가지 지표가 있을 수 있지만 로컬 개발 환경에 대한 가시성은 동일하지 않을 수 있습니다. 하지만 로컬 빌드
시간은 개발자 경험에 영향을 미치는 가장 중요한 요소 중 하나입니다.

로컬 빌드 시간 추적을 시작하려면 `tuist inspect build` 명령을 계획의 포스트 액션에 추가하여 활용할 수 있습니다:

![빌드 검사를 위한 사후
작업](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info Mise란?
<!-- -->
"빌드 설정 제공 위치"를 실행 파일 또는 기본 빌드 대상으로 설정하여 Tuist에서 빌드 구성을 추적할 수 있도록 하는 것이 좋습니다.
<!-- -->
:::

::: info Mise란?
<!-- -->
1} 생성된 프로젝트</LocalizedLink>를 사용하지 않는 경우 빌드 실패 시 사후 체계 작업이 실행되지 않습니다.
<!-- -->
:::
> 
> Xcode에 문서화되지 않은 기능을 사용하면 이 경우에도 실행할 수 있습니다. 다음과 같이 관련 `project.pbxproj` 파일에 있는
> 스키마의 `BuildAction` 에서 `runPostActionsOnFailure` 속성을 `YES` 로 설정합니다:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/)를 사용하는 경우, 스크립트의 환경 설정 후속 작업에서 `tuist`를 활성화해야 합니다:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip Mise와 프로젝트 경로
<!-- -->
`PATH` 환경 변수는 스키마 Post Action에 의해 상속되지 않으므로 Mise의 절대 경로를 사용해야 하며, 이는 Mise 설치 방법에
따라 달라집니다. 또한 프로젝트의 Target에서 빌드 설정을 상속하여 $SRCROOT가 가리키는 디렉토리에서 Mise를 실행할 수 있도록 하는
것을 잊지 마세요.
<!-- -->
:::


이제 로컬 빌드는 Tuist 계정에 로그인되어 있는 한 추적됩니다. 이제 Tuist 대시보드에서 빌드 시간에 액세스하여 시간이 지남에 따라
어떻게 변화하는지 확인할 수 있습니다:


::: tip
<!-- -->
대시보드에 빠르게 액세스하려면 CLI에서 `tuist project show --web` 을 실행합니다.
<!-- -->
:::

![빌드 인사이트가 있는 대시보드](/images/guides/features/insights/builds-dashboard.png)

## Generated 프로젝트 {#generated-projects}

::: info Mise란?
<!-- -->
자동 생성된 Scheme에는 `tuist inspect build` Post Action이 자동으로 포함됩니다.
<!-- -->
:::
> 
> 자동 생성된 스키마에서 분석을 추적하는 데 관심이 없는 경우
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> Generation 옵션을 사용하여 비활성화하세요.

사용자 정의된 스키마와 함께 생성된 프로젝트를 사용하는 경우 다음과 같이 분석에 대한 Post Action을 설정할 수 있습니다:

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
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise를 사용하지 않는 경우 스크립트를 다음과 같이 간소화할 수 있습니다:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## 지속 통합 {#continuous-integration}

CI에 대한 빌드 및 테스트 분석을 추적하려면 CI가
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>되었는지
확인해야 합니다.

또한 다음 중 하나를 수행해야 합니다:
- `xcodebuild` 동작을 호출할 때
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 명령을 사용합니다.
- `xcodebuild` 호출에 `-resultBundlePath` 을 추가합니다.

`xcodebuild` 가 `-resultBundlePath` 없이 프로젝트를 빌드하면 필요한 활동 로그와 결과 번들 파일이 생성되지 않습니다.
` tuist inspect build` Post Action은 빌드를 분석하는 데 이러한 파일이 필요합니다.
