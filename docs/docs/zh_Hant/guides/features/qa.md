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
Tuist QA 目前處於早期預覽階段。請至 [tuist.dev/qa](https://tuist.dev/qa) 註冊以取得使用權限。
<!-- -->
:::

優質的行動應用程式開發仰賴全面的測試，但傳統方法存在局限。單元測試雖快速且具成本效益，卻無法涵蓋真實的使用情境。驗收測試與人工品質保證雖能彌補這些缺口，但耗費大量資源且難以擴展。

Tuist 的 QA
代理程式透過模擬真實用戶行為來解決此挑戰。它能自主探索您的應用程式、識別介面元素、執行逼真的互動操作，並標記潛在問題。此方法有助於您在開發初期即發現錯誤與可用性問題，同時避免傳統驗收與
QA 測試所帶來的額外負擔與維護壓力。

## 先決條件{#prerequisites}

要開始使用 Tuist QA，您需要：
- 在您的 PR CI 工作流程中設定上傳
  <LocalizedLink href="/guides/features/previews">預覽</LocalizedLink>，以便測試人員進行測試
- <LocalizedLink href="/guides/integrations/gitforge/github">將 </LocalizedLink>
  與 GitHub 整合，以便您能直接從您的 PR 觸發代理程式

## 用法{#usage}

Tuist QA 目前可直接從 PR 觸發。當您的 PR 已關聯預覽後，您可以在該 PR 上留言`/qa test I want to test feature
A` 來觸發 QA 代理程式：

![QA 觸發註解](/images/guides/features/qa/qa-trigger-comment.png)

該評論包含一個連結，可導向即時會話頁面，您可在該頁面即時查看 QA 代理程式的工作進度及其發現的任何問題。代理程式執行完畢後，會將結果摘要發佈回拉取請求：

![QA 測試摘要](/images/guides/features/qa/qa-test-summary.png)

作為儀表板報告的一部分（PR 評論會連結至此），您將獲得一份問題清單和時間軸，以便您查閱問題確切的發生經過：

![QA 時間軸](/images/guides/features/qa/qa-timeline.png)

您可以在我們的公開儀表板中查看針對
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS
應用程式</LocalizedLink> 進行的所有 QA 執行紀錄：https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QA 代理程式會自主運行，一旦啟動便無法透過額外提示中斷。
我們會在執行過程中提供詳細日誌，協助您了解代理程式與您的應用程式如何互動。這些日誌對於迭代您的應用程式情境及測試提示語，以更有效地引導代理程式的行為，具有重要價值。若您對代理程式在您的應用程式中的表現有任何回饋，請透過
[GitHub Issues](https://github.com/tuist/tuist/issues)、我們的 [Slack
社群](https://slack.tuist.dev) 或 [社群論壇](https://community.tuist.dev) 告知我們。
<!-- -->
:::

### 應用程式上下文{#app-context}

代理程式可能需要更多關於您應用程式的背景資訊，才能順利操作。我們提供三種應用程式的背景資訊類型：
- 應用程式說明
- 憑證
- 啟動參數群組

所有這些設定皆可在專案的儀表板設定中進行調整（`Settings` >`QA` ）。

#### 應用程式說明{#app-description}

應用程式描述是用來提供關於應用程式功能及運作方式的額外背景資訊。這是一個長篇文字欄位，在啟動代理程式時會作為提示的一部分傳遞。例如：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 憑證{#credentials}

若測試人員需要登入應用程式以測試某些功能，您可以提供憑證供其使用。若系統偵測到需要登入，測試人員將自動填入這些憑證。

#### 啟動參數群組{#launch-argument-groups}

在執行代理程式之前，系統會根據您的測試提示選取啟動參數群組。例如，如果您不希望代理程式反覆登入，從而浪費您的代幣和執行器時間，您可以在此處指定您的憑證。如果代理程式識別到應以已登入狀態啟動會話，它將在啟動應用程式時使用憑證啟動參數群組。

![啟動參數群組](/images/guides/features/qa/launch-argument-groups.png)

這些啟動參數是標準的 Xcode 啟動參數。以下是一個示例，說明如何使用它們來自動登入：

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
