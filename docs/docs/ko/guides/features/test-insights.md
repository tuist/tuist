---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# 테스트 인사이트 {#test-insights}

::: warning 요구 사항
<!-- -->
- 1}Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

테스트 인사이트는 느린 테스트를 식별하거나 실패한 CI 실행을 신속하게 파악함으로써 테스트 스위트의 상태를 모니터링하는 데 도움을 줍니다.
테스트 스위트가 커질수록 점진적으로 느려지는 테스트나 간헐적 실패와 같은 추세를 포착하기가 점점 어려워집니다. Tuist Test
Insights는 빠르고 안정적인 테스트 스위트를 유지하는 데 필요한 가시성을 제공합니다.

테스트 인사이트를 통해 다음과 같은 질문에 답할 수 있습니다:
- 테스트 속도가 느려졌나요? 어떤 테스트가?
- 어떤 테스트가 불안정하여 주의가 필요한가요?
- CI 실행이 실패한 이유는 무엇인가요?

## 설정 {#setup}

시험 추적을 시작하려면 `tuist inspect test` 명령을 계획의 시험 사후 조치에 추가하여 활용할 수 있습니다:

![테스트 검사를 위한 사후
조치](/images/guides/features/insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/)를 사용하는 경우, 스크립트의 환경 설정 후속 작업에서 `tuist`를 활성화해야 합니다:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip Mise와 프로젝트 경로
<!-- -->
`PATH` 환경 변수는 스키마 Post Action에 의해 상속되지 않으므로 Mise의 절대 경로를 사용해야 하며, 이는 Mise 설치 방법에
따라 달라집니다. 또한 프로젝트의 Target에서 빌드 설정을 상속하여 $SRCROOT가 가리키는 디렉토리에서 Mise를 실행할 수 있도록 하는
것을 잊지 마세요.
<!-- -->
:::

이제 튜이스트 계정에 로그인되어 있는 한 테스트 실행이 추적됩니다. 튜이스트 대시보드에서 테스트 인사이트에 액세스하여 시간이 지남에 따라 어떻게
발전하는지 확인할 수 있습니다:

![테스트 인사이트가 포함된 대시보드](/images/guides/features/insights/tests-dashboard.png)

전체 트렌드 외에도 CI에서 실패 또는 느린 테스트를 디버깅할 때와 같이 각 개별 테스트에 대해 자세히 살펴볼 수도 있습니다:

![테스트 세부 정보](/images/guides/features/insights/test-detail.png)

## Generated 프로젝트 {#generated-projects}

::: info Mise란?
<!-- -->
자동 생성된 Scheme에는 `tuist inspect build` Post Action이 자동으로 포함됩니다.
<!-- -->
:::
> 
> 자동 생성된 스키마에서 분석을 추적하는 데 관심이 없는 경우
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">buildInsightsDisabled</LocalizedLink>
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
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise를 사용하지 않는 경우 스크립트를 다음과 같이 간소화할 수 있습니다:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## 지속적 통합 {#continuous-integration}

CI에 대한 빌드 및 테스트 분석을 추적하려면 CI가
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>되었는지
확인해야 합니다.

또한 다음 중 하나를 수행해야 합니다:
- `xcodebuild` 동작을 호출할 때
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 명령을 사용합니다.
- `xcodebuild` 호출에 `-resultBundlePath` 을 추가합니다.

`xcodebuild` 명령을 `-resultBundlePath` 옵션 없이 프로젝트 테스트 시, 필요한 결과 번들 파일이 생성되지 않습니다.
`tuist inspect test` 사후 작업은 테스트 분석을 위해 해당 파일을 요구합니다.
