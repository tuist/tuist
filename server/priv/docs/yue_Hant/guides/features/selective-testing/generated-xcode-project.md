---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，只執行受你最新改動影響的 Xcode 和生成專案測試，讓持續整合在數秒內提供回饋。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project}

隨著專案規模增長，每次推送都執行所有測試會變得難以擴展。Tuist 的<.localized_link href="/guides/features/projects/hashing">選擇性測試</.localized_link>只會執行自上次成功測試執行以來目標有所變更的測試，這基於 Tuist 的哈希演算法。

若要在你的<.localized_link href="/guides/features/projects">產生專案</.localized_link>中執行選擇性測試，請使用 `tuist test` 指令。該指令會以與<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>相同的方式為你的專案<.localized_link href="/guides/features/projects/hashing">計算雜湊</.localized_link>，並在成功時持久化這些雜湊值，以確定未來執行中哪些內容已變更。在未來的執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，並僅執行自上次成功測試執行以來已變更的測試。

`tuist test` 直接與<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>整合，利用本地或遠端儲存中的二進位檔來縮短執行測試套件時的建置時間。將選擇性測試與模組快取結合，可以大幅減少在 CI 上執行測試所需的時間。

如果你的測試僅針對模擬器執行，請傳遞 `--destination simulator`，這樣 `tuist test` 就只會使用和下載快取二進位檔的模擬器切片。請參閱<.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。對於每個 `--destination` 值，選擇性測試的雜湊值都是相同的。

## 分離建置與測試工作 {#separate-build-and-test-jobs}

選擇性測試支援分離的建置與測試工作。在建置工作中執行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置輸出的產品一起保存。該圖表攜帶了選擇性測試所需的雜湊值，因此測試工作無需重新產生專案或解析 Swift Package 依賴項即可確定要執行哪些目標。

Tuist 在 `--build-only` 期間會將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` bundle 內部。
- 位於衍生資料的 `Build/Products/` 目錄下，緊鄰每個 `.xctestrun` 檔案。

將任一輸出與建置產品一起快取，並在測試工作中將相同路徑傳遞給 `--without-building`。兩種形式皆可運作：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置工作使用普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會退而重新產生專案，以便仍能計算受影響的目標。這種回退機制需要在測試工作上解析 Swift Package 依賴項，因此請先執行 `tuist install` 或在各工作之間快取 `Tuist/.build`。

該圖表反映的是建置時的原始碼樹狀結構。請針對與建置工作相同的提交執行測試工作——如果兩者之間的原始碼發生偏移，雜湊值將不再與原始碼匹配，選擇性測試可能會跳過實際上會在較新原始碼中失敗的測試。

### 我應該使用哪個旗標？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它們在可移植性與管線便利性之間取捨：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新管線。** 這是一個自包含的目錄：建置好的 `.xctest` 二進位檔及其 `.xctestrun` 檔案都位於其中，路徑相對於 bundle 根目錄，因此無論移至何處都能保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有圍繞衍生資料建立的管線，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 的頂層寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置的測試 bundle。在另一個工作中重用意味著保持 `Build/Products/` 中的路徑不變。

如果你是從頭開始，建議使用 `-testProductsPath`。如果你正在將 Tuist 接入已快取衍生資料的現有管線，只要建置工作透過 `tuist test --build-only` 執行，`-xctestrun` 就能獲得相同的快速路徑。

任一種輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會略過這些旗標，並透過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組層級與檔案層級的粒度**
>
> 由於無法偵測測試與原始碼之間的程式內依賴關係，預設選擇性測試的最大粒度僅限於目標層級。[覆蓋率策略](#coverage-based-test-selection)將其縮小到單一測試。因此，我們建議保持目標小而專注，以最大化選擇性測試的效益。


## 基於覆蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期存取**
>
> 基於覆蓋率的測試選擇處於早期存取階段。請聯繫我們以在你的帳戶中啟用此功能。在啟用之前，該策略的行為與預設選擇性測試相同。

預設情況下，選擇性測試會跳過雜湊值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在先前執行中程式碼覆蓋率未涵蓋任何你變更所触及檔案的測試。它適用於 XCTest 和 XCUITest 測試，以及為其設置的[Swift Testing](#swift-testing)測試套件中的測試。在 `Tuist.swift` 中啟用：

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

- **上傳覆蓋率。** Tuist 根據先前執行上傳的覆蓋率來選擇測試，因此如果 manifest 將 `.coverage()` 設置為 `upload: false`，`tuist test` 將無法載入。
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 或更新版本**，並由你的測試目標[連結](#linking-testcoverageattribution)。它會記錄每個測試執行了哪些檔案，並跳過 Tuist 未選擇的測試。沒有它的目標只會像預設情況一樣被整體跳過。
- **足夠頻繁的完整測試執行。** 使用 `tuist test --no-selective-testing` 的執行會執行所有測試並成為基準。選擇性執行會與其提交歷史中同一平台上的近期執行進行比較，如果沒有基準則不應用覆蓋率。在哪裡以及多頻繁地執行它們取決於你的團隊工作方式，例如在預設分支的每次提交、每晚或在發布分支上。我們建議在預設分支上執行：那裡的完整執行也能在變更發布前捕捉到覆蓋率無法看到的問題，例如測試所依賴的 fixture 或服務。

啟用該策略後，`tuist test` 會跳過雜湊值已通過的目標，然後詢問 Tuist 你的變更會影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被建置。新測試、上次失敗的測試、位於已變更測試檔案中的測試，以及沒有記錄覆蓋率的測試始終會執行。

有時不會應用覆蓋率，輸出結果會說明原因：雜湊值未通過的目標中的所有測試都會執行，就像預設的選擇性測試一樣。這會在以下情況發生：同一平台上沒有近期的基準、變更涉及超過 5,000 個檔案，或影響任何測試的檔案發生變更，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。若要執行所有測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單一執行報告的覆蓋率工具（包括 Xcode）假設整個測試套件已執行，因此選擇性執行的報告會省略其跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">程式碼覆蓋率</.localized_link> 反而會從先前的執行中延續被跳過測試目標的覆蓋率，方法是使用它在每次執行時記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標層級覆蓋率</.localized_link>。

### 連結 TestCoverageAttribution {#linking-testcoverageattribution}

將套件加入 `Tuist/Package.swift`，並鎖定其次版本，因為 0.x 次版本發行可能會改變其記錄的內容：

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

然後將其加入你的測試目標，切勿加入應用程式目標：

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Tuist 預設將套件連結為靜態框架。僅包含 XCTest 的目標不會參考套件中的任何內容，因此連結器會將其丟棄，連同記錄和跳過功能一併移除。你可以將 `-ObjC` 加入測試目標的 `OTHER_LDFLAGS`，或在 `Tuist/Package.swift` 中動態連結該套件：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing 沒有可供函式庫掛接的觀察 API，因此其測試需要在測試套件上使用 TestCoverageAttribution 的 `.coverageAttribution` 特性。該特性會適用於嵌套在擁有該特性的套件內的套件。沒有該特性的套件中的測試不會記錄每個測試的覆蓋率，因此每當其目標執行時，這些測試也會執行。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **測試不得重疊。** Swift Testing 預設會平行執行處理序中的測試，而覆蓋率計數器無法區分同時執行的測試，因此這些測試不會記錄自身的覆蓋率並始終執行。`.serialized` 僅對套件內部的測試進行排序，因此只有當目標只有一個套件時才足夠。XCTest 不需要任何設定：平行測試會在各自的處理序中執行每個測試複製品。
- **按測試目標關閉平行化。** Xcode 將此設定應用於每個測試目標，因此你可以僅針對希望逐個測試選擇的目標關閉它，而方案中的其他目標則繼續平行執行。無需單獨的方案。在可測試目標上設定 `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`，這也會在沒有複製品的情況下執行該目標的 XCTest 測試。Tuist 產生的方案會從專案的 `testingOptions` 取得此設定，除非它們包含 `.parallelizable` 或 `.swiftTestingOnlyParallelizable`，否則預設為關閉。將 `-parallel-testing-enabled YES` 或 `NO` 傳遞給 `tuist test` 會覆寫該次執行中每個目標的設定。
- **跳過功能需要 Swift 6.3 (Xcode 26.4) 或更新版本。** 該特性會取消 Tuist 未選擇的測試並將其報告為已跳過。在較早的版本中，測試仍會記錄覆蓋率，但 Tuist 未選擇的測試仍會執行。

### 始終執行的測試 {#tests-that-always-run}

覆蓋率僅能看到測試執行的程式碼。如果測試的實際輸入是 fixture、資源、網路或環境，即使沒有任何受覆蓋的程式碼發生變更，測試也可能失敗。將其標記為不可跳過，即使 Tuist 未選擇它，它也會執行：

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

這僅適用於正在執行的測試目標。雜湊值已通過的目標，或 Tuist 未選擇其中任何測試的目標，會被整體跳過且永遠不會啟動，因此其不可跳過的測試也不會執行。

請參閱 [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) 以了解所有選項。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git Forge 整合**
>
> 若要獲得自動的 Pull/Merge Request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 Git Forge 整合：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


當你的 Tuist 專案與 Git 平台（例如 [GitHub](https://github.com)）連接，並開始在 CI 工作流程中使用 `tuist test` 時，Tuist 會直接在你的 pull/merge request 中發布評論，列出已執行和已跳過的測試：![包含 Tuist Preview 連結的 GitHub app 評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前快取的測試目標顯示為未命中時，測試執行頁面上的 **選擇性測試** 標籤可讓你深入檢視產生雜湊值的輸入。展開一行會顯示每個元件的子雜湊值——原始碼、依賴項、環境變數、專案和目標設定、Info.plist、權限、標頭檔等——以便你找出執行之間發生漂移的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕，匯出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次執行之間的 JSON 是確認測試目標雜湊值漂移時哪個輸入發生變更的最快方法。
