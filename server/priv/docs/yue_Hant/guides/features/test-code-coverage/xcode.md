---
{
  "title": "Xcode 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "將 Xcode 專案的代碼覆蓋率上載至 Tuist，並按檔案及提交追蹤。"
}
---
# Xcode 程式碼覆蓋率 {#xcode-code-coverage}

程式碼覆蓋率會告訴你測試執行咗邊啲程式碼行。Tuist 會上傳每次測試執行的行覆蓋率，並將同一個 commit 嘅多次執行合併成一個數值，涵蓋整個專案、每個 target 同每個檔案。儀表板嘅 **Code Coverage** 頁面會按 commit 顯示，並呈現每個分支嘅趨勢。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你用 Tuist 生成專案，請改為參考 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">generated project guide</.localized_link>：佢會量度來自 binary cache 嘅程式碼，並延續 selective testing 跳過嘅測試 target 覆蓋率。

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

`TUIST_COVERAGE_UPLOAD` 環境變數（`1` 或 `0`）優先於該選項，例如可以用嚟喺處理來自 fork 嘅 pull request 嘅 job 中關閉上傳。

然後喺你 scheme 嘅 test action 中開啟 **Code Coverage**（**Edit Scheme › Test › Options**），或者喺執行時傳遞 `-enableCodeCoverage YES`，並透過 `tuist xcodebuild test` 執行你嘅測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 會上傳該次執行收集到嘅覆蓋率，連同其測試結果一併上傳。

### 喺 CI 上完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個 job：每個 scheme、每個分片或每個平台各一個。Tuist 無法得知最後一個 job 何時已完成匯報，所以你需要主動通知佢。當某個 commit 嘅所有測試 job 都完成後，喺一個依賴晒呢啲 job 嘅 job 中執行以下指令：

```sh
tuist coverage complete
```

喺 commit 完成之前，其覆蓋率會顯示為 **In progress**，並且不會納入該分支嘅趨勢計算。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">generated project guide</.localized_link> 描述咗每種狀態。

## 跳過嘅測試 {#skipped-tests}

當一次執行使用 `-skip-testing` 跳過測試時，佢量度到嘅範圍會少過該 commit 測試所涵蓋嘅範圍，而 Tuist 亦無法將呢啲測試從之前嘅執行中延續落去。該 commit 嘅覆蓋率會標示為 **Incomplete**，除非該 commit 另有其他執行跑過呢啲測試。為咗保持 commit 完整，請確保每個 commit 至少有一次執行跑晒所有測試。

被 quarantine 跳過嘅測試完全唔會計入覆蓋率，所以佢哋永遠唔會令到 commit 變成 **Incomplete**。

## 效能影響 {#performance-impact}

收集覆蓋率會增加額外開銷，主要係喺測試完成之後，當 Xcode 寫入覆蓋率報告而同埋 Tuist 匯出覆蓋率數據嗰陣。構建同運行測試所需嘅時間同冇開啟覆蓋率時差不多。

## 查詢覆蓋率 {#querying}

`tuist coverage` 指令會讀取儀表板顯示嘅內容。如果冇指定 `--commit`，佢哋會讀取 `--branch` 或你預設分支最新已完成嘅 commit：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

個別測試執行自身嘅覆蓋率可以喺 `tuist test show <test-run-id>` 中查看。

所有指令都接受 `--json` 以便進行腳本處理。
