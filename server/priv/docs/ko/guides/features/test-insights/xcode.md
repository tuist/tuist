---
{
  "title": "Xcode 테스트 인사이트",
  "titleTemplate": ":title · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 인사이트로 Xcode 테스트 분석을 추적하여 느리고 불안정한 테스트를 식별하세요."
}
---
# Xcode 테스트 인사이트 {#xcode-test-insights}

Tuist Test Insights는 느린 테스트를 식별하거나 실패한 CI 실행을 빠르게 파악하여 테스트 스위트의 상태를 모니터링할 수 있는 Xcode 테스트 분석 기능을 제공합니다. 테스트 스위트가 커질수록 점차 느려지는 테스트나 간헐적인 실패와 같은 추세를 파악하기가 점점 더 어려워집니다. Tuist Test Insights는 빠르고 안정적인 테스트 스위트를 유지하는 데 필요한 가시성을 제공합니다.

Test Insights를 사용하면 다음과 같은 질문에 답할 수 있습니다:
- 테스트가 더 느려졌나요? 어떤 테스트인가요?
- 어떤 테스트가 불안정해서 주의가 필요한가요?
- CI 실행이 실패한 이유는 무엇인가요?

## 설정 {#setup}

테스트 추적을 시작하려면 스킴의 테스트 사후 동작에 `tuist inspect test` 명령어를 추가하여 활용할 수 있습니다:

![테스트 검사용 사후 동작](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/)를 사용하는 경우, 스크립트에서 사후 동작 환경 내에서 `tuist`를 활성화해야 합니다:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise 및 프로젝트 경로**
>
> 환경의 `PATH` 환경 변수는 스킴 사후 동작으로 상속되지 않으므로 Mise 설치 방식에 따라 달라지는 Mise의 절대 경로를 사용해야 합니다. 또한 $SRCROOT가 가리키는 디렉터리에서 Mise를 실행할 수 있도록 프로젝트의 타겟에서 빌드 설정을 상속하는 것을 잊지 마세요.

Tuist 계정에 로그인되어 있는 동안에는 테스트 실행이 추적됩니다. Tuist 대시보드에서 테스트 인사이트에 접근하고 시간이 지남에 따라 어떻게 변화하는지 확인할 수 있습니다:

![테스트 인사이트가 포함된 대시보드](/images/guides/features/build-insights/tests-dashboard.png)

전체적인 추세 외에도 CI에서 실패나 느린 테스트를 디버깅할 때와 같이 각 개별 테스트를 깊이 있게 살펴볼 수 있습니다:

![테스트 세부 정보](/images/guides/features/build-insights/test-detail.png)

## 생성된 프로젝트 {#generated-projects}

> [!NOTE]
> 자동 생성된 스킴에는 `tuist inspect test` 사후 동작이 자동으로 포함됩니다.

>
> 자동 생성된 스킴에서 테스트 인사이트를 추적하지 않으려면 [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 생성 옵션을 사용하여 비활성화하세요.

사용자 정의 스킴이 있는 생성된 프로젝트를 사용하는 경우, 테스트 인사이트를 위한 사후 동작을 설정할 수 있습니다:

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

Mise를 사용하지 않는 경우, 스크립트를 다음과 같이 단순화할 수 있습니다:

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

CI에서 테스트 인사이트를 추적하려면 CI가 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link>인지 확인해야 합니다.

또한 다음 중 하나가 필요합니다:
- `xcodebuild` 작업을 호출할 때 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> 명령어를 사용하세요.
- `xcodebuild` 호출에 `-resultBundlePath`를 추가하세요.

`xcodebuild`가 `-resultBundlePath` 없이 프로젝트를 테스트하면 필요한 결과 번들 파일이 생성되지 않습니다. `tuist inspect test` 사후 동작은 테스트를 분석하기 위해 이러한 파일이 필요합니다.

### Git 히스토리 {#git-history}

CI에서 Tuist는 체크아웃의 커밋 히스토리(커밋 SHA, 부모 커밋, 커밋 날짜, 실행 및 해당 풀 리퀘스트의 기본 브랜치)도 업로드합니다. 파일 내용, 커밋 메시지 또는 작성자는 업로드되지 않습니다. 이는 Tuist가 머지 큐에서 테스트된 커밋과 같이 기본 브랜치에 도착한 커밋을 식별하는 데 사용됩니다. Tuist는 체크아웃에 이미 있는 히스토리를 읽으며, 체크아웃에 기본 브랜치가 없는 경우 원격 저장소에 최신 커밋(`git ls-remote`)을 요청합니다. 코드 커버리지를 제외한 경우에는 히스토리를 가져오지 않습니다.

| 변수 | 효과 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 히스토리를 읽거나 업로드하지 않습니다. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 원격 저장소에 연결하지 않고 체크아웃만 읽습니다. |
