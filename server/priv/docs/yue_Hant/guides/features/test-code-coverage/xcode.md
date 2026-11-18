---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上傳至 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 代碼覆蓋率 {#xcode-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

代碼覆蓋率會告訴你測試執行了你代碼中的哪些行。Tuist 會上傳每次測試執行的行覆蓋率，並將一個 commit 的所有執行合併為單一數值，涵蓋整個項目、每個 target 和每個檔案。儀表板的 **代碼覆蓋率** 頁面會按 commit 顯示，並展示每個分支的趨勢。

> [!TIP]
> 如果你使用 Tuist 生成項目，請改為參閱 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成項目指南</.localized_link>：它會測量來自二進制緩存的代碼，並延續選擇性測試跳過的測試 target 的覆蓋率。

## 設定 {#setup}

### 收集覆蓋率 {#collect-coverage}

在你的 `Tuist.swift` 中開啟覆蓋率上傳功能。預設情況下它是關閉的：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）的優先級高於該選項，例如可用於在運行來自 fork 的 pull request 的 job 中關閉上傳。

然後在 scheme 的測試動作中開啟 **代碼覆蓋率**（**Edit Scheme › Test › Options**），或在運行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 運行你的測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次執行收集的覆蓋率及其測試結果。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時已報告，因此你需要告訴它。當一個 commit 的所有測試 job 都完成後，在依賴所有這些 job 的 job 中運行以下命令：

```sh
tuist coverage complete
```

在 commit 完成之前，其覆蓋率會顯示為 **進行中**，並且不會納入其分支的趨勢中。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成項目指南</.localized_link> 描述了每種狀態。

## 跳過的測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 跳過測試時，它測量的範圍少於該 commit 測試所覆蓋的範圍，且 Tuist 無法從較早的執行中延續這些測試。該 commit 的覆蓋率將顯示為 **不完整**，除非該 commit 的另一次執行了它們。為了保持 commit 完整，請在每個 commit 至少一次執行中運行所有測試。

被隔離跳過的測試完全不屬於覆蓋率的一部分，因此它們永遠不會導致 commit 顯示為 **不完整**。

## 性能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要發生在測試結束後，此時 Xcode 正在寫入其覆蓋率報告，而 Tuist 正在導出覆蓋率。構建和運行測試所需的時間與未開啟此功能時大致相同。

## 查詢覆蓋率 {#querying}

`tuist coverage` 命令會讀取儀表板顯示的內容。如果不指定 `--commit`，它們會讀取 `--branch` 的最新完整 commit，或者你的默認分支的最新完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

所有命令都接受 `--json` 以便用於腳本。
