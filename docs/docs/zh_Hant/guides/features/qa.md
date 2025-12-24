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
Tuist QA 目前處於早期預覽階段。請至 [tuist.dev/qa](https://tuist.dev/qa) 註冊以取得存取權限。
<!-- -->
:::

優質的行動應用程式開發有賴於全面的測試，但傳統的方法有其限制。單元測試既快速又符合成本效益，但卻會遺漏實際的使用者情境。驗收測試和手動 QA
可以捕捉這些缺口，但它們需要大量資源，而且規模不大。

Tuist 的 QA
代理可透過模擬真實使用者行為來解決這項挑戰。它能自主探索您的應用程式、識別介面元素、執行真實的互動，並標示潛在的問題。此方法可協助您在開發初期找出錯誤和可用性問題，同時避免傳統驗收和
QA 測試的開銷和維護負擔。

## 先決條件{#prerequisites}

要開始使用 Tuist QA，您需要
- 設定從您的 PR CI 工作流程上傳
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink>，然後代理就可以使用它來進行測試
- <LocalizedLink href="/guides/integrations/gitforge/github">與 GitHub 整合</LocalizedLink>，讓您可以直接從 PR 觸發代理程式

## 使用方式{#usage}

Tuist QA 目前是直接從 PR 觸發。一旦您有了與 PR 相關聯的預覽，您就可以在 PR 上註解`/qa test I want to test
feature A` 來觸發 QA 代理：

![QA觸發評論](/images/guides/features/qa/qa-trigger-comment.png)。

註解包含一個即時會話連結，您可以即時看到 QA 代理的進度和發現的任何問題。代理程式完成執行後，會將結果摘要貼回 PR：

![QA 測試摘要](/images/guides/features/qa/qa-test-summary.png)。

作為儀表板中報告的一部分，也就是 PR 評論所連結的部分，您將獲得問題清單和時間軸，因此您可以檢視問題到底是如何發生的：

![QA 時間線](/images/guides/features/qa/qa-timeline.png)!

您可以在我們的公開儀表板中看到我們為
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS 應用程式</LocalizedLink>所執行的所有 QA 測試： https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QA
代理可自主運行，一旦啟動，就不會被其他提示中斷。我們會在整個執行過程中提供詳細的記錄，以協助您瞭解代理如何與您的應用程式互動。這些記錄對於迭代您的應用程式上下文和測試提示以更好地引導代理程式的行為非常有價值。如果您對於代理程式如何執行您的應用程式有任何意見，請透過
[GitHub Issues](https://github.com/tuist/tuist/issues)、[Slack
社群](https://slack.tuist.dev) 或 [社群論壇](https://community.tuist.dev)告知我們。
<!-- -->
:::

### 應用程式情境{#app-context}

代理可能需要更多有關應用程式的情境，才能很好地瀏覽應用程式。我們有三種應用程式上下文：
- 應用程式說明
- 證書
- 啟動爭論群組

所有這些都可以在專案的儀表板設定中設定 (`Settings` >`QA`)。

#### 應用程式說明{#app-description}

App description 用於提供額外的內容，說明您的應用程式的功能和運作方式。這是一個長格式的文字欄位，會在啟動代理程式時作為提示的一部分傳送。範例如下

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 證書{#credentials}

如果代理需要登入應用程式以測試某些功能，您可以提供憑證供代理使用。如果代理發現需要登入，就會填入這些憑證。

#### 啟動爭論群組{#launch-argument-groups}

根據您在執行代理程式前的測試提示，選擇啟動參數群組。例如，如果您不希望代理程式反覆登入，浪費您的代號和執行時間，您可以在此指定憑證。如果代理認知到它應該以登入方式啟動會話，它會在啟動應用程式時使用憑證啟動參數群組。

[啟動參數群組](/images/guides/features/qa/launch-argument-groups.png)。

這些啟動參數是標準的 Xcode 啟動參數。以下是如何使用它們來自動登入的範例：

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
