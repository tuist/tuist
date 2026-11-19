---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上傳至 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 代碼覆蓋率 {#xcode-code-coverage}

程式碼覆蓋率會告訴你測試執行了哪些程式碼行。Tuist 會上傳每次測試執行的行覆蓋率，並將同一個 commit 的多次執行合併為單一數值，適用於整個專案、每個 target 及每個檔案。儀表板的 **Code Coverage** 頁面會按 commit 顯示，並呈現每個 branch 的趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你使用 Tuist 產生專案，請改參閱<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">generated project guide</.localized_link>：它會測量來自 binary cache 的程式碼，並延續被選擇性測試略過的測試 target 之覆蓋率。

## 設定 {#setup}

### 收集覆蓋率 {#collect-coverage}

喺你嘅 `Tuist.swift` 中開啟覆蓋率上傳。預設係關閉嘅：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）優先於該選項，例如可以用嚟喺運行來自 fork 嘅 pull request 嘅 job 中關閉上傳。

然後喺你 scheme 嘅測試動作中開啟 **Code Coverage**（**Edit Scheme › Test › Options**），或者喺運行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 運行你嘅測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次運行收集到嘅覆蓋率，連同其測試結果一併上傳。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法判斷最後一個 job 何時匯報，所以你需要告訴佢。當一個 commit 嘅所有測試 job 都完成後，喺一個依賴晒所有呢啲 job 嘅 job 中運行以下命令：

```sh
tuist coverage complete
```

喺 commit 完成之前，其覆蓋率會顯示為 **In progress**，並且不會納入其分支嘅趨勢中。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">generated project guide</.localized_link> 描述咗每種狀態。

## 跳過嘅測試 {#skipped-tests}

當一次運行使用 `-skip-testing` 跳過測試時，佢測量嘅範圍少於該 commit 測試所覆蓋嘅範圍，而且 Tuist 無法從 earlier run 延續呢啲測試。該 commit 嘅覆蓋率會係 **Incomplete**，除非該 commit 有另一次運行執行咗佢哋。為咗保持 commit 完整，請確保每個 commit 至少有一次運行執行咗所有測試。

被隔離跳過嘅測試完全唔屬於覆蓋率嘅一部分，所以佢哋永遠唔會令 commit 變成 **Incomplete**。

## 性能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要係喺測試完成之後，當 Xcode 寫入其覆蓋率報告而 Tuist 導出覆蓋率數據時。構建同運行測試所需嘅時間同冇開啟覆蓋率時差唔多。

## 查詢覆蓋率 {#querying}

`tuist coverage` 命令會讀取 dashboard 顯示嘅內容。如果冇 `--commit`，佢哋會讀取 `--branch` 嘅最新完整 commit，或者你嘅默認分支嘅最新完整 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

一次測試執行自身嘅覆蓋率可以喺 `tuist test show <test-run-id>` 中查看。

所有命令都接受 `--json` 以便腳本化處理。
