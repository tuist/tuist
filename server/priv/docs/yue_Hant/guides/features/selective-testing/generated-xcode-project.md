---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 選擇性測試，只運行受你最近改動影響嘅 Xcode 同生成專案測試，令持續整合喺幾秒內提供反饋。"
}
---
# 生成的 Xcode 專案 {#generated-xcode-project}

隨著專案規模擴大，每次推送都執行所有測試會變得難以擴展。Tuist 的選擇性測試只會執行自上次成功測試執行以來目標有變更的測試，這基於 Tuist 的 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

若要使用你的 <.localized_link href="/guides/features/projects">生成專案</.localized_link> 選擇性地執行測試，請使用 `tuist test` 指令。該指令會以與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同的方式為你的專案進行 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，並在成功時持久化這些雜湊值，以確定未來執行中哪些內容發生了變更。在未來的執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，並僅執行自上次成功測試執行以來發生變更的測試。

`tuist test` 直接與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，以利用來自本機或遠端儲存空間的二進位檔案，從而改善執行測試套件時的建置時間。將選擇性測試與模組快取結合，可以大幅減少在 CI 上執行測試所需的時間。

如果你的測試僅針對模擬器目標，請傳遞 `--destination simulator`，以便 `tuist test` 僅使用和下載快取二進位檔案的模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。對於每個 `--destination` 值，選擇性測試的雜湊值都是相同的。

## 分離建置和測試工作 {#separate-build-and-test-jobs}

選擇性測試支援分離的建置和測試工作。在建置工作中執行 `tuist test --build-only`，以便 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置產生的產品一起持久化。該圖表攜帶選擇性測試所需的雜湊值，因此測試工作無需重新生成專案或解析 Swift Package 依賴項即可確定要執行哪些目標。

在 `--build-only` 期間，Tuist 會在兩個位置寫入圖表：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` bundle 內部。
- 位於衍生資料的 `Build/Products/` 目錄下每個 `.xctestrun` 檔案旁邊。

將任一輸出與建置產品一起快取，並在測試工作中將相同路徑傳遞給 `--without-building`。兩種形式均可運作：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置工作使用普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會退回到重新生成專案，以便仍能計算受影響的目標。這種回退需要在測試工作上解析 Swift Package 依賴項，因此請先執行 `tuist install` 或在各工作之間快取 `Tuist/.build`。

該圖表反映建置時的原始碼樹狀結構。請針對與建置工作相同的提交執行測試工作——如果兩者之間的原始碼發生偏移，雜湊值將不再與原始碼匹配，選擇性測試可能會跳過實際上會在較新原始碼上失敗的測試。

### 我應該使用哪個旗標？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它们在可移植性和管道便利性之間權衡：

- **`-testProductsPath` (`.xctestproducts`) — 推薦用於新管道。** 這是一個自包含目錄：建置的 `.xctest` 二進位檔案及其 `.xctestrun` 檔案位於其中，路徑相對於 bundle 根目錄，因此無論其最終位於何處都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有圍繞衍生資料構建的管道，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 的頂層寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置的測試 bundle。在另一個工作中重用意味著保持 `Build/Products/` 中的路徑完整無損。

如果你是從頭開始，建議使用 `-testProductsPath`。如果你將 Tuist 整合到已快取衍生資料的現有管道中，只要建置工作通過 `tuist test --build-only` 運行，`-xctestrun` 就能獲得相同的快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些旗標，並通過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組級與檔案級粒度**
>
> 由於無法檢測測試與原始碼之間的代碼內依賴關係，默認選擇性測試的最大粒度處於目標級別。[覆蓋率策略](#coverage-based-test-selection) 將其縮小到單個 XCTest 測試。因此，我們建議保持目標小而專注，以最大化選擇性測試的收益。


## 基於覆蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期訪問**
>
> 基於覆蓋率的測試選擇處於早期訪問階段。請聯繫我們以為你的帳戶啟用此功能。在啟用之前，該策略的行為類似於默認的選擇性測試。

默認情況下，選擇性測試會跳過雜湊值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在 earlier run 中的代碼覆蓋率未涵蓋你變更所涉及的任何文件的 XCTest 和 XCUITest 測試。在 `Tuist.swift` 中啟用它：

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

- **覆蓋率上傳。** Tuist 根據 earlier runs 上傳的覆蓋率來選擇測試，因此如果 manifest 將 `.coverage()` 設置為 `upload: false`，`tuist test` 將無法加載。
- 由你的測試目標鏈接的 **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 或更高版本**。它記錄每個測試執行的文件，並跳過 Tuist 未選擇的測試。沒有它的目標只會像默認情況下一樣被整體跳過。
- **在你的默認分支上執行測試而不進行選擇。** 在那裡以及任何不應跳過測試的其他分支上執行 `tuist test --no-selective-testing`。這些執行會運行每個測試，並成為後續執行比較的基準。

啟用該策略後，`tuist test` 會跳過雜湊值已通過的目標，然後詢問 Tuist 你的變更會影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被建置。新測試、上次失敗的測試、位於已變更測試文件中的測試以及沒有記錄覆蓋率的測試始終會運行。Swift Testing 測試在其目標運行時始終運行。

有時不會應用覆蓋率，輸出會說明原因：雜湊值未通過的目標的每個測試都會運行，如同默認的選擇性測試。當同一平台上沒有最近的基準、變更是涉及超過 5,000 個文件，或可能影響任何測試的文件（如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生變更時，就會發生這種情況。若要運行每個測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單一執行報告的覆蓋率工具（包括 Xcode）假設整個測試套件已運行，因此選擇性執行的報告會省略它跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 會從較早的執行中延續被跳過測試目標的覆蓋率，方法是使用它在每次執行時記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標層級覆蓋率</.localized_link>。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git Forge**
>
> 若要獲取自動的 Pull/Merge Request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。


一旦你的 Tuist 專案連接到如 [GitHub](https://github.com) 等 Git 平台，並開始在 CI 工作流程中使用 `tuist test`，Tuist 就會直接在你的 Pull/Merge Request 中發佈評論，其中包括哪些測試已運行以及哪些已跳過：![帶有 Tuist Preview 連結的 GitHub App 評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前快取的測試目標顯示為未命中時，測試執行頁面上的 **選擇性測試** 標籤可讓你深入檢視產生雜湊值的輸入。展開一行會顯示每個組件的子雜湊值——原始碼、依賴項、環境變數、專案和目標設定、Info.plist、權限、標頭檔等——以便你找出在兩次執行之間發生變化的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕，匯出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次執行之間的 JSON 是確認測試目標雜湊值變化時哪個輸入發生改變的最快方法。
