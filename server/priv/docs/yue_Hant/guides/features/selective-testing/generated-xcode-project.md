---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，只運行受你最新改動影響嘅 Xcode 同生成專案測試，令持續整合喺幾秒內提供反饋。"
}
---
# 生成的 Xcode 項目 {#generated-xcode-project}

隨著專案規模增長，每次推送都執行所有測試會變得難以擴展。Tuist 的<.localized_link href="/guides/features/projects/hashing">選擇性測試</.localized_link>只會執行自上次成功測試執行以來目標有變更的測試，這是基於 Tuist 的哈希演算法。

要在你的<.localized_link href="/guides/features/projects">生成項目</.localized_link>中選擇性地運行測試，請使用 `tuist test` 命令。該命令會以與<.localized_link href="/guides/features/cache/module-cache">模塊緩存</.localized_link>相同的方式對你的項目進行<.localized_link href="/guides/features/projects/hashing">哈希</.localized_link>處理，並在成功後持久化這些哈希值，以便在未來的運行中確定哪些內容發生了變化。在未來的運行中，`tuist test` 會透明地使用這些哈希值來篩選測試，只運行自上次成功測試執行以來發生變化的測試。

`tuist test` 直接與<.localized_link href="/guides/features/cache/module-cache">模塊緩存</.localized_link>集成，利用本地或遠程存儲中的二進制文件來縮短運行測試套件時的構建時間。將選擇性測試與模塊緩存結合使用，可以大幅減少在 CI 上運行測試所需的時間。

如果你的測試僅針對模擬器，請傳遞 `--destination simulator`，這樣 `tuist test` 就只會使用和下載緩存二進制文件的模擬器切片。參見<.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。對於每個 `--destination` 值，選擇性測試的哈希值都是相同的。

## 分離構建和測試任務 {#separate-build-and-test-jobs}

選擇性測試支持分離的構建和測試任務。在構建任務中運行 `tuist test --build-only`，以便 Tuist 能夠將 `selective-testing-graph.json` 文件與構建產生的產品一起持久化。該圖表攜帶了選擇性測試所需的哈希值，因此測試任務無需重新生成項目或解析 Swift Package 依賴項來確定要運行哪些目標。

在 `--build-only` 期間，Tuist 會在兩個位置寫入圖表：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` 包內部。
- 位於派生數據的 `Build/Products/` 目錄下每個 `.xctestrun` 文件旁邊。

將任一輸出與構建產品一起緩存，並在測試任務中將相同的路徑傳遞給 `--without-building`。兩種形式均可工作：

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當構建任務使用普通的 `xcodebuild build-for-testing` 而不是 `tuist test --build-only` 時），它會回退到重新生成項目，以便仍然可以計算受影響的目標。這種回退需要在測試任務上解析 Swift Package 依賴項，因此請先運行 `tuist install` 或在任務之間緩存 `Tuist/.build`。

該圖表反映了構建時的源代碼樹狀態。請針對與構建任務相同的提交運行測試任務——如果兩者之間的源代碼發生偏移，哈希值將不再與源代碼匹配，選擇性測試可能會跳過實際上會在新源代碼上失敗的測試。

### 我應該使用哪個標誌？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它们在可移植性和流水線便利性之間進行了權衡：

- **`-testProductsPath` (`.xctestproducts`) — 推薦用於新流水線。** 這是一個自包含的目錄：構建的 `.xctest` 二進制文件及其 `.xctestrun` 文件位於其中，路徑相對於包根目錄，因此無論它最終位於何處都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已經有一個圍繞派生數據構建的流水線，請使用它。** `xcodebuild build-for-testing` 默認情況下會在 `<derivedData>/Build/Products/` 的頂部寫入一個 `.xctestrun`，並將其指向位於該樹其他位置的測試包。在另一個任務中重用它意味著保持 `Build/Products/` 中的路徑不變。

如果你是從頭開始，首選 `-testProductsPath`。如果你將 Tuist 接入到已經緩存了派生數據的現有流水線中，只要構建任務通過 `tuist test --build-only` 運行，`-xctestrun` 就能獲得同樣的快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些標誌，並通過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模塊級與文件級粒度**
>
> 由於無法檢測測試和源代碼之間的代碼內依賴關係，默認選擇性測試的最大粒度為目標級別。[覆蓋率策略](#coverage-based-test-selection)將其縮小到單個 XCTest 測試。因此，我們建議保持你的目標小而專注，以最大化選擇性測試的收益。


## 基於覆蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期訪問**
>
> 基於覆蓋率的測試選擇處於早期訪問階段。請聯繫我們以為你的賬戶啟用此功能。在啟用之前，該策略的行為與默認選擇性測試相同。

默認情況下，選擇性測試會跳過哈希值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在 earlier run 中的代碼覆蓋率未涵蓋你更改所涉及的任何文件的 XCTest 和 XCUITest 測試。在 `Tuist.swift` 中啟用它：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

該策略要求：

- **覆蓋率上傳。** Tuist 根據 earlier runs 上傳的覆蓋率來選擇測試，因此如果清單將 `.coverage()` 設置為 `upload: false`，`tuist test` 將無法加載。
- **由你的測試目標鏈接的 [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 或更高版本**。它記錄每個測試執行了哪些文件，並跳過 Tuist 未選擇的測試。沒有它的目標只會像默認情況下一樣被整體跳過。
- **在你的默認分支上運行不帶選擇的測試。** 在那裡以及任何不應跳過測試的其他分支上運行 `tuist test --no-selective-testing`。這些運行會執行每個測試，並成為後續運行比較的基準。

啟用該策略後，`tuist test` 會跳過哈希值已通過的目標，然後詢問 Tuist 你的更改會影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被構建。新測試、上次失敗的測試、更改過的測試文件中的測試以及沒有記錄覆蓋率的測試始終會運行。Swift Testing 測試在其目標運行時也會運行。

有時不會應用覆蓋率，輸出會說明原因：哈希值未通過的目標的每個測試都會運行，就像默認選擇性測試一樣。這發生在沒有同一平台上的近期基準時，當更改涉及超過 5,000 個文件時，或者當可能影響任何測試的文件（如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生更改時。要運行每個測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單次運行報告的覆蓋率工具（包括 Xcode 內置的工具）假設整個測試套件已運行，因此選擇性運行的報告會省略它跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 會將跳過測試目標的覆蓋率從 earlier run 延續下來，方法是使用它在每次運行中記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標級別覆蓋率</.localized_link>。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要集成 Git Forge**
>
> 要獲得自動的 Pull/Merge Request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 項目</.localized_link> 與 Git Forge 集成：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


一旦你的 Tuist 項目連接到 Git 平台（例如 [GitHub](https://github.com)），並且你開始在 CI 工作流中使用 `tuist test`，Tuist 就會直接在你的 Pull/Merge Request 中發布評論，其中包括哪些測試已運行以及哪些已跳過：![帶有 Tuist Preview 鏈接的 GitHub App 評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當以前緩存的測試目標顯示為未命中時，測試運行頁面上的 **選擇性測試** 標籤頁可讓你深入查看生成哈希值的輸入。展開一行會顯示每個組件的子哈希值——源代碼、依賴項、環境變量、項目和目標設置、Info.plist、權限、頭文件等——以便你準確找出兩次運行之間發生漂移的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕，導出每個選擇性測試目標及其哈希值和子哈希值。比較兩次運行之間的 JSON 是確認測試目標哈希值漂移時哪個輸入發生更改的最快方法。
