---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA{#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA 目前處於早期預覽階段。請至 [tuist.dev/qa](https://tuist.dev/qa) 註冊以獲取使用權限。
<!-- -->
:::

優質的行動應用程式開發仰賴全面測試，但傳統方法存在局限。單元測試雖快速且成本效益高，卻無法涵蓋真實使用情境。驗收測試與人工品質保證雖能彌補此缺口，卻需大量資源且難以擴展。

Tuist 的 QA
代理程式透過模擬真實使用者行為來解決此挑戰。它能自主探索您的應用程式，識別介面元素，執行真實互動，並標記潛在問題。此方法有助於在開發初期發現錯誤與可用性問題，同時避免傳統驗收測試與品質保證測試所帶來的額外負擔與維護成本。

## 先決條件{#prerequisites}

要開始使用 Tuist QA，您需要：
- 設定從您的 PR CI 工作流程上傳
  <LocalizedLink href="/guides/features/previews">預覽</LocalizedLink>，以便代理程式用於測試
- <LocalizedLink href="/guides/integrations/gitforge/github">將</LocalizedLink>與GitHub整合，即可直接從您的PR觸發代理程式

## 用法{#usage}

Tuist QA 目前直接從 PR 觸發。當您的 PR 關聯預覽後，可透過在 PR 中留言觸發 QA 代理程式：`/qa test 我想測試功能 A`

![QA觸發註解](/images/guides/features/qa/qa-trigger-comment.png)

該註解包含即時會話連結，您可透過此連結查看 QA 代理程式的執行進度及偵測到的問題。當代理程式完成執行後，將把結果摘要回傳至 PR：

![QA 測試摘要](/images/guides/features/qa/qa-test-summary.png)

作為儀表板報告的一部分（此報告由PR評論連結至），您將獲得問題清單與時間軸，以便查核問題確切發生的經過：

![QA 時間軸](/images/guides/features/qa/qa-timeline.png)

您可在我們的公開儀表板查看所有針對
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS
應用程式</LocalizedLink> 執行的品質保證測試：https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QA 代理程式執行時具備自主性，啟動後無法透過額外提示中斷其運作。
我們提供執行過程的詳細日誌，協助您理解代理程式與應用程式的互動方式。這些日誌對於迭代應用程式上下文及測試提示語極具價值，有助於更精準引導代理程式行為。若您對代理程式在應用程式中的表現有任何意見，請透過[GitHub
Issues](https://github.com/tuist/tuist/issues)、我們的[Slack社群](https://slack.tuist.dev)或[社群論壇](https://community.tuist.dev)告知我們。
<!-- -->
:::

### 應用程式上下文{#app-context}

客服人員可能需要更多應用程式背景資訊才能順利操作。我們提供三種類型的應用程式背景：
- 應用程式說明
- 憑證
- 啟動參數群組

所有設定皆可於專案控制台進行調整（`設定` >`品質保證` ）。

#### 應用程式說明{#app-description}

應用程式說明用於提供額外背景資訊，闡述應用程式的功能與運作方式。此為長篇文字欄位，會在啟動代理程式時作為提示的一部分傳遞。範例如下：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 憑證{#credentials}

若代理程式需登入應用程式測試功能，可提供認證憑證供其使用。當代理程式偵測到需登入時，將自動填入這些憑證資訊。

#### 啟動參數群組{#launch-argument-groups}

啟動參數組會根據您在執行代理程式前的測試提示進行選取。例如，若您不希望代理程式反覆登入而浪費令牌和執行器分鐘數，可在此處指定憑證。當代理程式偵測到應以登入狀態啟動工作階段時，便會在啟動應用程式時使用憑證啟動參數組。

![啟動參數群組](/images/guides/features/qa/launch-argument-groups.png)

這些啟動參數是標準的 Xcode 啟動參數。以下範例示範如何運用這些參數實現自動登入：

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
