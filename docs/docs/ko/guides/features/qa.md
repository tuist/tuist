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
Tuist QA는 현재 초기 프리뷰 단계입니다. [tuist.dev/qa](https://tuist.dev/qa)에서 가입하여 이용하세요.
<!-- -->
:::

품질 높은 모바일 앱 개발은 포괄적인 테스트에 의존하지만, 기존 접근 방식에는 한계가 있습니다. 단위 테스트는 빠르고 비용 효율적이지만 실제
사용자 시나리오를 놓칩니다. 인수 테스트와 수동 QA는 이러한 간극을 포착할 수 있지만, 자원 집약적이며 확장성이 떨어집니다.

Tuist의 QA 에이전트는 실제 사용자 행동을 모방하여 이 과제를 해결합니다. 앱을 자율적으로 탐색하고 인터페이스 요소를 인식하며 현실적인
상호작용을 실행한 후 잠재적 문제를 표시합니다. 이 접근 방식은 개발 초기 단계에서 버그와 사용성 문제를 식별하는 동시에 기존 승인 및 QA
테스트의 오버헤드와 유지보수 부담을 피할 수 있도록 지원합니다.

## 필수 조건 {#prerequisites}

Tuist QA 사용을 시작하려면 다음을 수행해야 합니다:
- PR CI 워크플로에서
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> 업로드를
  설정하여 에이전트가 테스트에 활용할 수 있도록 하십시오.
- <LocalizedLink href="/guides/integrations/gitforge/github">Integrate</LocalizedLink>을
  GitHub와 연동하여 PR에서 직접 에이전트를 실행할 수 있도록 하세요

## 사용량 {#usage}

Tuist QA는 현재 PR에서 직접 트리거됩니다. PR에 미리보기가 연결되면, PR에 `/qa test I want to test
feature A` 로 댓글을 달아 QA 에이전트를 트리거할 수 있습니다:

![QA 트리거 코멘트](/images/guides/features/qa/qa-trigger-comment.png)

이 코멘트에는 QA 에이전트의 진행 상황과 발견된 문제를 실시간으로 확인할 수 있는 라이브 세션 링크가 포함되어 있습니다. 에이전트가 실행을
완료하면 결과 요약이 PR로 다시 게시됩니다:

![QA 테스트 요약](/images/guides/features/qa/qa-test-summary.png)

PR 코멘트가 연결하는 대시보드의 보고서 일부로, 문제 목록과 타임라인을 확인할 수 있으므로 문제가 정확히 어떻게 발생했는지 조사할 수
있습니다:

![QA 타임라인](/images/guides/features/qa/qa-timeline.png)

저희 <LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS
앱</LocalizedLink>에 대한 모든 QA 실행 내역은 공개 대시보드에서 확인하실 수 있습니다:
https://tuist.dev/tuist/tuist/qa

::: info Mise란?
<!-- -->
QA 에이전트는 자율적으로 실행되며 시작 후 추가 프롬프트로 중단할 수 없습니다. 에이전트가 앱과 어떻게 상호작용했는지 이해할 수 있도록 실행
과정 전반에 걸쳐 상세한 로그를 제공합니다. 이러한 로그는 앱 컨텍스트를 반복적으로 개선하고 에이전트의 행동을 더 잘 안내하기 위한 프롬프트
테스트에 유용합니다. 에이전트의 앱 수행 방식에 대한 피드백이 있으시면 [GitHub
Issues](https://github.com/tuist/tuist/issues), [Slack
커뮤니티](https://slack.tuist.dev) 또는 [커뮤니티 포럼](https://community.tuist.dev)을 통해
알려주십시오.
<!-- -->
:::

### 앱 컨텍스트 {#app-context}

에이전트가 앱을 원활하게 탐색하려면 앱에 대한 추가 컨텍스트가 필요할 수 있습니다. 앱 컨텍스트는 세 가지 유형이 있습니다:
- 앱 설명
- 자격 증명
- 인수 그룹 시작

이 모든 설정은 프로젝트 대시보드 설정에서 구성할 수 있습니다 (`Settings` > `QA`).

#### 앱 설명 {#app-description}

앱 설명은 앱의 기능과 작동 방식에 대한 추가 정보를 제공하는 용도입니다. 이는 챗봇을 시작할 때 프롬프트의 일부로 전달되는 장문 텍스트
필드입니다. 예시로는 다음과 같습니다:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 자격 증명 {#credentials}

에이전트가 일부 기능을 테스트하기 위해 앱에 로그인해야 하는 경우, 에이전트가 사용할 수 있는 인증 정보를 제공할 수 있습니다. 에이전트는
로그인 필요성을 인식하면 해당 인증 정보를 입력할 것입니다.

#### 런치 인자 그룹 {#launch-argument-groups}

에이전트 실행 전 테스트 프롬프트에 따라 런치 인자 그룹이 선택됩니다. 예를 들어, 에이전트가 반복적으로 로그인하여 토큰과 러너 시간을 낭비하지
않도록 하려면, 대신 여기에 자격 증명을 지정할 수 있습니다. 에이전트가 로그인된 상태로 세션을 시작해야 한다고 인식하면, 앱 실행 시 자격
증명 런치 인자 그룹을 사용합니다.

![Launch argument groups](/images/guides/features/qa/launch-argument-groups.png)

이러한 실행 인수는 표준 Xcode 실행 인수입니다. 자동 로그인에 사용하는 예시는 다음과 같습니다:

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
