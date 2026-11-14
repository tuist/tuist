---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上傳至 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 代碼覆蓋率 {#xcode-code-coverage}

程式碼覆蓋率會告訴你測試執行了你程式碼中的哪些行。Tuist 會上傳每次測試執行的行覆蓋率，並將一個 commit 的所有執行結果合併為單一數值，涵蓋整個專案、每個 target 及每個檔案。儀表板的 **Code Coverage** 頁面會按 commit 顯示這些數據，並呈現每個 branch 的趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你使用 Tuist 生成項目，請改為參閱<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">generated project guide</.localized_link>：它會測量來自 binary cache 的代碼，並延續選擇性測試跳過的測試 target 之覆蓋率。

## 設定 {#setup}

### 收集覆蓋率 {#collect-coverage}

在 `Tuist.swift` 中開啟覆蓋率上傳功能。預設為關閉：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）的優先級高於該選項，例如可用於在執行來自 fork 的 pull request 的 job 中關閉上傳。

然後在 scheme 的 test action 中開啟 **Code Coverage**（**Edit Scheme › Test › Options**），或在執行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次執行收集的覆蓋率及其測試結果。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個 job：每個 scheme、每個 shard 或每個平台各一個。Tuist 無法判斷最後一個 job 何時已回報，因此需要你明確告知。當一個 commit 的所有測試 job 都完成後，在依賴所有這些 job 的 job 中執行以下指令：

```sh
tuist coverage complete
```

在 commit 完成之前，其覆蓋率會顯示為 **In progress**，且不會納入該 branch 的趨勢中。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">generated project guide</.localized_link> 說明了每種狀態。

## 跳過的測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 跳過測試時，其測量的範圍會少於該 commit 測試所涵蓋的範圍，而 Tuist 無法從較早的執行中延續這些測試。該 commit 的覆蓋率會標示為 **Incomplete**，除非該 commit 另有其他執行跑了這些測試。要讓 commit 保持完整，請在每個 commit 至少一次執行中運行所有測試。

被隔離機制跳過的測試完全不計入覆蓋率，因此它們永遠不會讓 commit 變成 **Incomplete**。

## 效能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要發生在測試完成後，因為 Xcode 需要寫入覆蓋率報告，而 Tuist 需要匯出覆蓋率資料。建置和執行測試所需的時間與未開啟時大致相同。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示的內容。若沒有 `--commit`，它們會讀取 `--branch` 的最新完整 commit，或是你的預設 branch：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有指令都接受 `--json` 以便進行腳本處理。
