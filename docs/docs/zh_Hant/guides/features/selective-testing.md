---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 選擇性測試{#selective-testing}

隨著專案的成長，測試的數量也在增加。長久以來，在每個 PR 或推送到`主網站` 時執行所有測試需要數十秒的時間。但此解決方案無法擴充至團隊可能擁有的數千個測試。

每次在 CI 上執行測試時，您很可能會重新執行所有的測試，而不考慮變更的情況。Tuist 的選擇性測試會根據我們的
<LocalizedLink href="/guides/features/projects/hashing">hashing 演算法</LocalizedLink>，只執行上次成功執行測試之後有變更的測試，幫助您大幅加快執行測試的速度。

選擇性測試可以使用`xcodebuild` ，它支援任何 Xcode 專案，如果您使用 Tuist 產生專案，也可以使用`tuist test`
指令，它提供一些額外的便利，例如整合 <LocalizedLink href="/guides/features/cache">binary cache</LocalizedLink> 。要開始使用選擇性測試，請根據您的專案設定遵循指示：

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">專案生成</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
由於無法偵測測試與來源之間的程式碼內依賴關係，選擇性測試的最大粒度是在目標層級。因此，我們建議將您的目標保持在較小且集中的層級，以發揮選擇性測試的最大效益。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
測試覆蓋率工具假設整個測試套件一次執行，這使得它們與選擇性測試執行不相容 -
這表示使用測試選擇時，覆蓋率資料可能無法反映現實。這是已知的限制，但這並不表示您做錯了什麼。我們鼓勵團隊反思在此情境下，覆蓋率是否仍能帶來有意義的洞察力，如果是的話，請放心，我們已經在思考未來如何讓覆蓋率與選擇性執行正常運作。
<!-- -->
:::


## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git 平台</LocalizedLink>整合。
<!-- -->
:::

一旦您的 Tuist 專案與 Git 平台 (例如 [GitHub](https://github.com)) 連線，並開始使用 `tuist xcodebuild test` 或 `tuist test` 作為 CI 流程的一部分，Tuist 會直接在您的 pull/merge 請求中張貼註解，包括哪些測試已執行，哪些跳過：

![GitHub 應用程式註解與 Tuist 預覽連結](/images/guides/features/selective-testing/github-app-comment.png)
