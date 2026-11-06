---
{
  "title": "已生成的 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 選擇性測試，只執行受你最近變更影響的 Xcode 及已生成專案測試，讓持續整合於數秒內提供回饋。"
}
---
# 生成的 Xcode 專案 {#generated-xcode-project}

隨著專案增長，每次推送都執行所有測試會變得難以擴展。Tuist 的選擇性測試只會執行自上次成功測試執行以來目標已變更的測試，這是基於 Tuist 的 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

若要在你的 <.localized_link href="/guides/features/projects">生成專案</.localized_link> 中選擇性地執行測試，請使用 `tuist test` 指令。該指令會以與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同的方式為你的專案進行 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，並在成功時儲存這些雜湊值，以便在未來的執行中判斷哪些內容已變更。在未來的執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，並只執行自上次成功測試執行以來已變更的測試。

`tuist test` 直接整合 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>，利用你本地或遠端儲存中的二進位檔案來縮短執行測試套件時的建置時間。將選擇性測試與模組快取結合，可以大幅減少在 CI 上執行測試所需的時間。

如果你的測試只針對模擬器，請傳遞 `--destination simulator`，這樣 `tuist test` 就只會使用和下載快取二進位檔案中的模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。選擇性測試的雜湊值對於每個 `--destination` 值都是相同的。

## 分開建置和測試工作 {#separate-build-and-test-jobs}

選擇性測試支援分開的建置和測試工作。在建置工作中執行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置產生的產物一起儲存。該圖表攜帶了選擇性測試所需的雜湊值，因此測試工作無需重新生成專案或解析 Swift Package 依賴項來確定要執行哪些目標。

Tuist 在 `--build-only` 期間會將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` 套件內部。
- 位於衍生資料的 `Build/Products/` 目錄下，緊鄰每個 `.xctestrun` 檔案。

將任一輸出與建置產物一起快取，並在測試工作中將相同的路徑傳遞給 `--without-building`。兩種形式均可運作：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置工作使用了普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會退回到重新生成專案，以便仍能計算受影響的目標。這種回退需要在測試工作上解析 Swift Package 依賴項，因此請先執行 `tuist install` 或在各工作之間快取 `Tuist/.build`。

該圖表反映了建置時的原始碼樹狀結構。請針對與建置工作相同的提交執行測試工作——如果兩者之間的原始碼發生偏移，雜湊值將不再與原始碼匹配，選擇性測試可能會跳過實際上會在較新原始碼上失敗的測試。

### 我應該使用哪個旗標？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它們在可移植性和管道便利性之間權衡：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新管道。** 這是一個自包含的目錄：建置好的 `.xctest` 二進位檔案及其 `.xctestrun` 檔案都位於其中，路徑相對於套件根目錄，因此無論移動到何處都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已經有一個圍繞衍生資料構建的管道，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 的頂層寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置的測試套件。在另一個工作中重用意味著保持 `Build/Products/` 中的路徑完整無損。

如果你是從頭開始，建議使用 `-testProductsPath`。如果你是將 Tuist 整合到已經快取衍生資料的現有管道中，只要建置工作透過 `tuist test --build-only` 執行，`-xctestrun` 就能獲得同樣的快速路徑。

任一種輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些旗標，並透過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組級與檔案級粒度**
>
> 由於無法檢測測試與原始碼之間的代碼內依賴關係，預設選擇性測試的最大粒度僅限於目標級別。[覆蓋率策略](#coverage-based-test-selection) 將其細化至單個 XCTest 測試。因此，我們建議保持目標小而專注，以最大化選擇性測試的收益。


## 基於覆蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期存取**
>
> 基於覆蓋率的測試選擇處於早期存取階段。請聯絡我們以為你的帳戶啟用此功能。在啟用之前，該策略的行為與預設選擇性測試相同。

預設情況下，選擇性測試會跳過雜湊值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在先前執行中的代碼覆蓋率未涵蓋你變更所觸及的任何檔案的 XCTest 和 XCUITest 測試。在 `Tuist.swift` 中啟用它：

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

- **覆蓋率上傳。** Tuist 根據先前執行上傳的覆蓋率來選擇測試，因此如果清單將 `.coverage()` 設定為 `upload: false`，`tuist test` 將無法載入該清單。
- 由你的測試目標連結的 **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 或更高版本**。它記錄每個測試執行了哪些檔案，並跳過 Tuist 未選擇的測試。沒有它的目標只能像預設情況那樣被整體跳過。
- **在你的預設分支上不進行選擇地執行測試。** 在該分支以及任何不應跳過測試的其他分支上執行 `tuist test --no-selective-testing`。這些執行會運行每個測試，並成為後續執行比較的基準。

啟用該策略後，`tuist test` 會跳過雜湊值已通過的目標，然後詢問 Tuist 你的變更會影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被建置。新測試、上次失敗的測試、位於已變更測試檔案中的測試，以及沒有記錄覆蓋率的測試始終會執行。Swift Testing 測試在其目標運行時也會執行。

當覆蓋率無法做出決定時，輸出會說明原因。如果在同一平台上沒有最近的基準，或者當變更觸及超過 5,000 個檔案時，每個測試都會執行，以便該提交可以成為基準。當可能影響任何測試的檔案（例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生變更時，執行會使用預設的選擇性測試。若要執行每個測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單一執行報告的覆蓋率工具（包括 Xcode 的工具）假設整個測試套件已執行，因此選擇性執行的報告會省略被跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 改為從先前的執行中延續被跳過測試目標的覆蓋率，使用它在每次執行時記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標層級覆蓋率</.localized_link>。


## 拉取／合併請求評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git 平台**
>
> 若要取得自動的拉取／合併請求評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。


一旦你的 Tuist 專案與如 [GitHub](https://github.com) 等 Git 平台連接，並開始在 CI 工作流程中使用 `tuist test`，Tuist 就會直接在拉取／合併請求中發布評論，說明哪些測試已執行、哪些已跳過：![包含 Tuist Preview 連結的 GitHub 應用程式評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前已快取的測試目標顯示為未命中時，測試執行頁面上的 **選擇性測試** 分頁可讓你深入檢視產生雜湊值的輸入。展開資料列會顯示各元件的子雜湊值——原始碼、依賴項、環境變數、專案和目標設定、Info.plist、權限、標頭檔等——以便你找出在兩次執行之間發生變化的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕，匯出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次執行之間的 JSON 是確認測試目標雜湊值變化時哪個輸入發生改變的最快方法。
