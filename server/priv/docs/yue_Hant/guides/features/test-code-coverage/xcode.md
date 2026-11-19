---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上載至 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 程式碼覆蓋率 {#xcode-code-coverage}

程式碼覆蓋率會告訴你測試執行咗邊啲程式碼行。Tuist 會上傳每次測試執行的行覆蓋率，並將同一個 commit 嘅多次執行合併成一個數值，涵蓋整個專案、每個 target 同每個檔案。儀表板嘅 **程式碼覆蓋率** 頁面會按 commit 顯示數據，並展示每個分支嘅趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你用 Tuist 生成專案，請改為參閱 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成專案指南</.localized_link>：佢會量度來自二進制快取嘅程式碼，並延續選擇性測試跳過嘅測試 target 覆蓋率。

## 設定 {#setup}

### 收集覆蓋率 {#collect-coverage}

喺你嘅 `Tuist.swift` 入面開啟覆蓋率上傳功能。預設係關閉嘅：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）嘅優先級高過該選項，例如可以用嚟喺處理來自 fork 嘅 pull request 任務中關閉上傳。

然後喺你 scheme 嘅測試動作中開啟 **程式碼覆蓋率**（**Edit Scheme › Test › Options**），或者喺執行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行你嘅測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳測試執行所收集到嘅覆蓋率，連同測試結果一齊上載。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個任務：每個 scheme、每個分片或每個平台各有一個。Tuist 無法得知最後一個任務何時匯報，所以你需要主動告知。當某個 commit 嘅所有測試任務都完成後，喺一個依賴晒所有呢啲任務嘅任務中執行以下指令：

```sh
tuist coverage complete
```

該指令會從 checkout 嘅 `HEAD` 讀取 commit，即係你測試運行嗰個 commit；傳遞 `--commit <sha>` 可以指定另一個 commit。喺 commit 完成之前，其覆蓋率會顯示為 **進行中**，並且不會納入該分支嘅趨勢計算。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成專案指南</.localized_link> 描述了每種狀態。

## 跳過嘅測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 跳過測試時，佢量度到嘅覆蓋率會少於該 commit 測試所涵蓋嘅範圍，而 Tuist 無法將呢啲測試從 earlier run 延續落去。除非該 commit 有另一次執行運行咗呢啲測試，否則該 commit 嘅覆蓋率會係 **不完整**。為咗保持 commit 完整，請確保每個 commit 至少有一次執行運行咗所有測試。

被隔離機制跳過嘅測試根本唔會計入覆蓋率，所以佢哋永遠唔會令到 commit 變成 **不完整**。

## 性能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要係喺測試完成之後，當 Xcode 寫入覆蓋率報告而同埋 Tuist 匯出覆蓋率數據嗰陣。構建同運行測試所需嘅時間同冇開啟覆蓋率時差唔多。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。如果冇指定 `--commit`，佢哋會讀取 `--branch` 嘅最新已完成 commit，或者你預設分支嘅最新已完成 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

測試執行自身嘅覆蓋率可以喺 `tuist test show <test-run-id>` 中查看。

所有指令都接受 `--json` 以便腳本化處理。
