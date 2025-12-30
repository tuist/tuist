---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
현재 튜이스트 QA는 초기 프리뷰 버전입니다. tuist.dev/qa](https://tuist.dev/qa)에서 등록하여 액세스 권한을
얻으세요.
<!-- -->
:::

고품질 모바일 앱 개발은 포괄적인 테스트에 의존하지만 기존 접근 방식에는 한계가 있습니다. 단위 테스트는 빠르고 비용 효율적이지만 실제 사용자
시나리오를 놓칠 수 있습니다. 수락 테스트와 수동 QA는 이러한 차이를 포착할 수 있지만 리소스 집약적이고 확장성이 떨어집니다.

Tuist의 QA 에이전트는 실제 사용자 행동을 시뮬레이션하여 이 문제를 해결합니다. 이 에이전트는 자율적으로 앱을 탐색하고, 인터페이스 요소를
인식하고, 실제와 같은 상호작용을 실행하고, 잠재적인 문제에 플래그를 지정합니다. 이 접근 방식을 사용하면 개발 초기에 버그와 사용성 문제를
식별하는 동시에 기존 승인 및 QA 테스트의 오버헤드 및 유지 관리 부담을 피할 수 있습니다.

## 사전 요구 사항 {#prerequisites}

Tuist QA를 사용하려면 다음을 수행해야 합니다:
- PR CI 워크플로우에서
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> 업로드를
  설정하면 상담원이 테스트에 사용할 수 있습니다.
- <LocalizedLink href="/guides/integrations/gitforge/github">GitHub와 통합</LocalizedLink>하여
  PR에서 직접 에이전트를 트리거할 수 있습니다.

## 사용량 {#usage}

현재 튜이스트 QA는 PR에서 직접 트리거됩니다. PR과 연결된 미리 보기가 있으면 PR에 `/qa test 기능 A를 테스트하고 싶습니다`
라고 댓글을 달아 QA 에이전트를 트리거할 수 있습니다:

![QA 트리거 설명](/images/guides/features/qa/qa-trigger-comment.png)

댓글에는 실시간 세션으로 연결되는 링크가 포함되어 있어 QA 에이전트의 진행 상황과 발견된 문제를 실시간으로 확인할 수 있습니다. 에이전트가
실행을 완료하면 결과 요약이 PR에 다시 게시됩니다:

![QA 테스트 요약](/images/guides/features/qa/qa-test-summary.png)

PR 댓글이 링크되는 대시보드의 보고서에는 이슈 목록과 타임라인이 표시되므로 이슈가 정확히 어떻게 발생했는지 확인할 수 있습니다:

![QA 타임라인](/images/guides/features/qa/qa-timeline.png)

공개 대시보드(https://tuist.dev/tuist/tuist/qa)에서
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS 앱</LocalizedLink>에 대해 수행한 모든 QA 실행을 확인할 수 있습니다.

::: info Mise란?
<!-- -->
QA 에이전트는 자율적으로 실행되며 일단 시작되면 추가 프롬프트로 중단할 수 없습니다. 에이전트가 앱과 상호 작용하는 방식을 이해하는 데 도움이
되도록 실행 전반에 걸쳐 자세한 로그를 제공합니다. 이러한 로그는 앱 컨텍스트를 반복하고 프롬프트를 테스트하여 에이전트의 동작을 더 잘 안내하는
데 유용합니다. 에이전트가 앱에서 수행하는 방식에 대한 피드백이 있는 경우 [GitHub
이슈](https://github.com/tuist/tuist/issues), [Slack
커뮤니티](https://slack.tuist.dev) 또는 [커뮤니티 포럼](https://community.tuist.dev)을 통해
알려주시기 바랍니다.
<!-- -->
:::

### 앱 컨텍스트 {#app-context}

상담원이 앱을 잘 탐색하려면 앱에 대한 더 많은 컨텍스트가 필요할 수 있습니다. 앱 컨텍스트에는 세 가지 유형이 있습니다:
- 앱 설명
- 자격 증명
- 인수 그룹 시작

이 모든 설정은 프로젝트의 대시보드 설정에서 구성할 수 있습니다(`설정` > `QA`).

#### 앱 설명 {#app-description}

앱 설명은 앱의 기능 및 작동 방식에 대한 추가 컨텍스트를 제공하기 위한 것입니다. 상담원을 시작할 때 프롬프트의 일부로 전달되는 긴 형식의
텍스트 필드입니다. 예를 들면 다음과 같습니다:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 자격 증명 {#credentials}

상담원이 일부 기능을 테스트하기 위해 앱에 로그인해야 하는 경우 상담원이 사용할 자격 증명을 제공할 수 있습니다. 상담원이 로그인해야 한다고
인식하면 이러한 자격 증명을 입력합니다.

#### 인수 그룹 시작 {#launch-argument-groups}

실행 인수 그룹은 에이전트를 실행하기 전에 테스트 프롬프트에 따라 선택됩니다. 예를 들어 상담원이 반복적으로 로그인하여 토큰과 러너 시간을
낭비하지 않도록 하려면 여기에 자격 증명을 지정할 수 있습니다. 에이전트가 로그인한 세션을 시작해야 한다고 인식하면 앱을 시작할 때 자격 증명
시작 인수 그룹을 사용합니다.

![인수 그룹 시작](/images/guides/features/qa/launch-argument-groups.png)

이러한 실행 인수는 표준 Xcode 실행 인수입니다. 다음은 이 인수를 사용하여 자동으로 로그인하는 방법에 대한 예제입니다:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
