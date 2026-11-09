---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，僅執行受最新變更影響的 Xcode 與產生專案測試，讓持續整合在數秒內提供回饋。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project}

隨著專案規模擴大，在每次推送時執行所有測試會變得難以擴展。Tuist 的選擇性測試只會執行自上次成功測試執行以來目標已變更的測試，這是根據 Tuist 的 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link> 來判斷。

若要在你的 <.localized_link href="/guides/features/projects">產生的專案</.localized_link> 中選擇性地執行測試，請使用 `tuist test` 指令。該指令會以與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同的方式為你的專案進行 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，並在成功後持久化這些雜湊值，以便在未來的執行中判斷哪些內容已變更。在未來的執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，並僅執行自上次成功測試執行以來已變更的測試。

`tuist test` 直接與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，利用來自本機或遠端儲存空間的二進位檔來改善執行測試套件時的建置時間。將選擇性測試與模組快取結合，可以大幅縮短在 CI 上執行測試所需的時間。

如果你的測試僅針對模擬器目標，請傳遞 `--destination simulator`，讓 `tuist test` 僅使用和下載快取二進位檔的模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。對於每個 `--destination` 值，選擇性測試的雜湊值都是相同的。

## 分離建置與測試工作 {#separate-build-and-test-jobs}

選擇性測試支援分離的建置與測試工作。在建置工作中執行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置輸出的產品一起持久化。該圖表攜帶選擇性測試所需的雜湊值，因此測試工作無需重新產生專案或解析 Swift Package 相依性即可確定要執行哪些目標。

Tuist 在 `--build-only` 期間會將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` 套件內部。
- 位於衍生資料的 `Build/Products/` 目錄下，緊鄰每個 `.xctestrun` 檔案。

將任一輸出與建置產品一起快取，並在測試工作中將相同路徑傳遞給 `--without-building`。兩種形式皆可行：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置工作使用普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會回退到重新產生專案，以便仍能計算受影響的目標。這種回退需要在測試工作上解析 Swift Package 相依性，因此請先執行 `tuist install`，或在各工作之間快取 `Tuist/.build`。

該圖表反映建置時的原始碼樹狀結構。請針對與建置工作相同的提交執行測試工作——如果兩者之間的原始碼發生偏移，雜湊值將不再符合原始碼，導致選擇性測試可能會跳過實際上會在較新原始碼中失敗的測試。

### 我該使用哪個旗標？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它們在可移植性與流程便利性之間各有取捨：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新的流程。** 這是一個自包含的目錄：建置好的 `.xctest` 二進位檔及其 `.xctestrun` 檔案都位於其中，路徑相對於套件根目錄，因此無論移至何處都能保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有基於衍生資料建構的流程，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 的頂層寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置的測試套件。在另一個工作中重複使用它意味著必須保持 `Build/Products/` 中的路徑完整無損。

如果你是從頭開始，建議優先使用 `-testProductsPath`。如果你正在將 Tuist 整合到已快取衍生資料的現有流程中，只要建置工作透過 `tuist test --build-only` 執行，`-xctestrun` 就能獲得相同的快速路徑。

任一種輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會略過這些旗標，並透過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組層級與檔案層級的粒度**
>
> 由於無法偵測測試與原始碼之間的程式內相依性，預設選擇性測試的最大粒度為目標層級。[涵蓋率策略](#coverage-based-test-selection) 將其縮小到單一 XCTest 測試。因此，我們建議保持目標小而專注，以最大化選擇性測試的效益。


## 基於涵蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期存取**
>
> 基於涵蓋率的測試選擇處於早期存取階段。請聯絡我們以為你的帳戶啟用此功能。在啟用之前，該策略的行為與預設選擇性測試相同。

預設情況下，選擇性測試會跳過雜湊值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在先前執行中的程式碼涵蓋率未包含任何你變更所触及檔案的 XCTest 和 XCUITest 測試。在 `Tuist.swift` 中啟用它：

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

該策略需要：

- **上傳涵蓋率。** Tuist 根據先前執行上傳的涵蓋率來選擇測試，因此 `tuist test` 在載入設定 `.coverage()` 且 `upload: false` 的清單時會失敗。
- 由你的測試目標連結的 **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 或更新版本**。它會記錄每個測試執行了哪些檔案，並跳過 Tuist 未選擇的測試。沒有它的目標只會像預設情況那樣被整體跳過。
- **在你的預設分支上執行不含選擇性的測試。** 在該分支以及任何其他不應跳過測試的分支上執行 `tuist test --no-selective-testing`。這些執行會運行每個測試，並成為後續執行比較的基準。

啟用該策略後，`tuist test` 會跳過雜湊值已通過的目標，然後詢問 Tuist 你的變更會影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被建置。新測試、上次失敗的測試、位於已變更測試檔案中的測試，以及沒有記錄涵蓋率的測試始終會執行。Swift Testing 測試在其目標執行時也會執行。

有時不會套用涵蓋率，輸出結果會說明原因：雜湊值未通過的目標中的每個測試都會執行，這與預設選擇性測試相同。當同一平台上沒有最近的基準、變更触及超過 5,000 個檔案，或可能影響任何測試的檔案（例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生變更時，就會出現這種情況。若要執行每個測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試涵蓋率**
>
> 讀取單一執行報告的涵蓋率工具（包括 Xcode 內建的工具）會假設整個測試套件都已執行，因此選擇性執行的報告會省略被跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">程式碼涵蓋率</.localized_link> 則會從先前的執行中延續被跳過測試目標的涵蓋率，使用的是它在每次執行時記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標層級涵蓋率</.localized_link>。


## Pull/Merge Request 留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git 平台**
>
> 若要取得自動的 Pull/Merge Request 留言，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。


一旦你的 Tuist 專案與如 [GitHub](https://github.com) 等 Git 平台連接，並開始在 CI 工作流程中使用 `tuist test`，Tuist 就會直接在你的 Pull/Merge Request 中發布留言，其中包含已執行和已跳過的測試：![附有 Tuist Preview 連結的 GitHub App 留言](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前已快取的測試目標顯示為未命中時，測試執行頁面上的 **選擇性測試** 分頁可讓你深入檢視產生雜湊值的輸入項目。展開資料列會顯示各元件的子雜湊值——原始碼、相依性、環境變數、專案與目標設定、Info.plist、權限、標頭檔等——讓你能精確找出在兩次執行之間發生變化的輸入項目。

使用選擇性測試卡片頂端的 **複製為 JSON** 按鈕，匯出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次執行之間的 JSON 是確認測試目標雜湊值變化時哪個輸入項目發生改變的最快方法。
