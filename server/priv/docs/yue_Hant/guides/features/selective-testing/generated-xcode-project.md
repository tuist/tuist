---
{
  "title": "已生成嘅 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 選擇性測試，只執行受你最近改動影響嘅 Xcode 同已生成專案測試，令持續整合喺幾秒內提供反饋。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project}

當專案規模擴大，每次推送都執行所有測試會變得難以擴展。Tuist 嘅選擇性測試只會執行自上次成功測試執行以來目標有變更嘅測試，基於 Tuist 嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

要喺你嘅 <.localized_link href="/guides/features/projects">已產生專案</.localized_link> 上選擇性執行測試，請使用 `tuist test` 指令。該指令會以同 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同嘅方式為你的專案 <.localized_link href="/guides/features/projects/hashing">計算雜湊值</.localized_link>，成功後會持久化這些雜湊值，以便在未來運行時確定哪些內容已更改。在未來運行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，並只執行自上次成功測試執行以來發生變更的測試。

`tuist test` 直接與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，利用本地或遠端儲存中的二進制文件來縮短執行測試套件時的構建時間。將選擇性測試與模組快取結合，可以大幅減少 CI 上運行測試所需的時間。

如果你的測試只針對模擬器，請傳遞 `--destination simulator`，這樣 `tuist test` 就只會使用和下載快取二進制文件中適用於模擬器的部分。參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。對於每個 `--destination` 值，選擇性測試的雜湊值都是相同的。

## 分離構建和測試任務 {#separate-build-and-test-jobs}

選擇性測試支持分離的構建和測試任務。在構建任務中運行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 文件與構建產生的產品一起持久化。該圖表攜帶了選擇性測試所需的雜湊值，因此測試任務無需重新生成專案或解析 Swift Package 依賴項來確定需要運行哪些目標。

Tuist 會在 `--build-only` 期間將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` bundle 內部。
- 位於衍生數據 `Build/Products/` 目錄下每個 `.xctestrun` 文件旁邊。

將任一輸出與構建產品一起快取，並在測試任務中將相同路徑傳遞給 `--without-building`。兩種形式均可行：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當構建任務使用普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會回退到重新生成專案，以便仍能計算受影響的目標。這種回退需要在測試任務上解析 Swift Package 依賴項，因此請先運行 `tuist install` 或在任務之間快取 `Tuist/.build`。

該圖表反映的是構建時的源代碼樹狀態。請確保測試任務針對與構建任務相同的 commit 運行——如果兩者之間的源代碼發生偏移，雜湊值將不再與源代碼匹配，選擇性測試可能會跳過實際上在新源代碼下會失敗的測試。

### 我應該使用哪個標誌？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它們在可移植性和流水線便利性之間取捨：

- **`-testProductsPath` (`.xctestproducts`) — 推薦用於新流水線。** 這是一個自包含目錄：構建的 `.xctest` 二進制文件及其 `.xctestrun` 文件都位於其中，路徑相對於 bundle 根目錄，因此無論移動到何處都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有基於衍生數據構建的流水線，請使用此選項。** `xcodebuild build-for-testing` 默認會在 `<derivedData>/Build/Products/` 頂部寫入一個 `.xctestrun`，並將其指向位於該樹其他位置的測試 bundle。在另一個任務中重用意味着要保持 `Build/Products/` 中的路徑完整無損。

如果你是從頭開始，建議使用 `-testProductsPath`。如果你正在將 Tuist 集成到已快取衍生數據的現有流水線中，只要構建任務通過 `tuist test --build-only` 運行，`-xctestrun` 就能獲得同樣的快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些標誌，並通過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組級與文件級粒度**
>
> 由於無法檢測測試與源代碼之間的代碼內依賴關係，默認選擇性測試的最大粒度為目標級別。[覆蓋率策略](#coverage-based-test-selection) 將其細化到單個測試。因此，我們建議保持目標小而專注，以最大化選擇性測試的收益。


## 基於覆蓋率的測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期訪問**
>
> 基於覆蓋率的測試選擇處於早期訪問階段。請聯繫我們以為你的帳戶啟用此功能。在啟用之前，該策略的行為與默認選擇性測試相同。

默認情況下，選擇性測試會跳過雜湊值已通過的整個測試目標。`.coverage()` 策略更進一步：在剩餘的測試目標中，它還會跳過那些在先前運行中的代碼覆蓋率未涵蓋你更改所涉及的任何文件的測試。它適用於 XCTest 和 XCUITest 測試，以及為其設置好的套件中的 [Swift Testing](#swift-testing) 測試。在 `Tuist.swift` 中啟用它：

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

- **上傳覆蓋率。** Tuist 根據先前運行上傳的覆蓋率來選擇測試，因此如果 manifest 將 `.coverage()` 設置為 `upload: false`，`tuist test` 將無法加載。
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 或更高版本**，並由你的測試目標 [鏈接](#linking-testcoverageattribution)。它記錄每個測試執行了哪些文件，並跳過 Tuist 未選擇的測試。沒有它的目標只會像默認情況那樣被整體跳過。
- **足夠頻繁的全量測試執行。** 使用 `tuist test --no-selective-testing` 運行的測試會執行所有測試並成為基準。選擇性運行會與其 commit 歷史中同一平台上的近期運行進行比較，如果沒有基準則不應用覆蓋率。在哪裡以及多頻繁地運行它們取決於你團隊的工作方式，例如在默認分支的每次 commit、每晚或在發布分支上。我們建議在默認分支上運行：那裏的全量運行還能在更改發布之前捕捉到覆蓋率無法看到的問題，例如測試依賴的 fixture 或服務。

啟用該策略後，`tuist test` 會跳過雜湊值已通過的目標，然後詢問 Tuist 你的更改可能影響剩餘目標中的哪些測試。沒有受影響測試的目標不會被構建。新測試、上次失敗的測試、位於已更改測試文件中的測試，以及沒有記錄覆蓋率的測試始終會運行。

有時不會應用覆蓋率，輸出會說明原因：雜湊值未通過的目標中的所有測試都會運行，就像默認選擇性測試一樣。當同一平台上沒有近期基準、更改涉及超過 5,000 個文件，或可能影響任何測試的文件（例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生更改時，就會出現這種情況。要運行所有測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單次運行報告的覆蓋率工具（包括 Xcode 的工具）假設整個測試套件都已運行，因此選擇性運行的報告會省略它跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 則會從先前的運行中繼承已跳過測試目標的覆蓋率，使用的是它在每次運行中記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標級別覆蓋率</.localized_link>。

### 鏈接 TestCoverageAttribution {#linking-testcoverageattribution}

將包添加到 `Tuist/Package.swift`，並鎖定到其次要版本，因為 0.x 次要版本的發布可能會更改其記錄的內容：

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

然後將其添加到你的測試目標中，切勿添加到應用目標：

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

Tuist 默認將包鏈接為靜態框架。僅包含 XCTest 的目標不會引用包中的任何內容，因此鏈接器會將其丟棄，連同記錄和跳過功能一起丟棄。要么將 `-ObjC` 添加到測試目標的 `OTHER_LDFLAGS`，要么在 `Tuist/Package.swift` 中動態鏈接包：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing 沒有庫可以加入的觀察 API，因此其測試需要在套件上使用 TestCoverageAttribution 的 `.coverageAttribution` 特性。該特性適用於嵌套在具有該特性的套件中的套件。沒有該特性的套件中的測試不會記錄每個測試的覆蓋率，因此每當其目標運行時它們都會運行。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **測試不得重疊。** Swift Testing 默認並行運行進程中的測試，而覆蓋率計數器無法區分同時運行的測試，因此這些測試不會記錄自己的覆蓋率並始終運行。`.serialized` 僅對套件自身的測試進行排序，因此只有當目標只有一個套件時才足夠。XCTest 不需要任何設置：並行測試會在各自的進程中運行每個測試克隆。
- **按測試目標關閉並行化。** Xcode 將設置應用於每個測試目標，因此你可以僅針對希望逐個選擇測試的目標關閉它，而方案中的其他目標繼續並行運行。不需要單獨的方案。在可測試目標上設置它，`.testableTarget(target: "CheckoutTests", parallelization: .disabled)`，這也會在沒有克隆的情況下運行該目標的 XCTest 測試。Tuist 生成的方案從項目的 `testingOptions` 獲取此設置，除非它們包含 `.parallelizable` 或 `.swiftTestingOnlyParallelizable`，否則默認為關閉。將 `-parallel-testing-enabled YES` 或 `NO` 傳遞給 `tuist test` 會覆蓋該次運行中每個目標的設置。
- **跳過需要 Swift 6.3 (Xcode 26.4) 或更高版本。** 該特性會取消 Tuist 未選擇的測試並將它們報告為已跳過。在較早的版本中，測試仍然記錄覆蓋率，但 Tuist 未選擇的測試仍會運行。

### 始終運行的測試 {#tests-that-always-run}

覆蓋率只能看到測試執行的代碼。如果測試的真實輸入是 fixture、資源、網絡或環境，即使沒有任何被覆蓋的代碼發生更改，測試也可能失敗。將其標記為不可跳過，即使 Tuist 未選擇它，它也會運行：

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

它僅適用於運行的測試目標。雜湊值已通過的目標，或 Tuist 未選擇其中任何測試的目標，會被整體跳過且從不啟動，因此其不可跳過的測試也不會運行。

查看 [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) 以了解所有選項。

### 檢查選擇 {#inspecting-a-selection}

測試運行的「選擇性測試」標籤頁顯示覆蓋率選擇了什麼以及原因。相同數據也可通過 CLI 獲取，使用 `--json` 進行腳本編寫，並通過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 服務器</.localized_link> 提供給代理：

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

當未應用覆蓋率時，測試仍計為基於覆蓋率的選擇：其原因會說明覆蓋率無法決定的原因，例如 `tracked_file_changed`。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git forge 集成**
>
> 要獲得自動的 pull/merge request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 項目</.localized_link> 與 Git forge 集成：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


一旦你的 Tuist 項目與 GitHub 等 Git 平台（如 [GitHub](https://github.com)）連接，並且你開始在 CI 工作流中使用 `tuist test`，Tuist 將直接在你的 pull/merge requests 中發布評論，包括哪些測試已運行以及哪些已跳過：![帶有 Tuist Preview 鏈接的 GitHub 應用評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前緩存的測試目標顯示為未命中時，測試運行頁面上的 **選擇性測試** 標籤頁允許你深入查看產生雜湊值的輸入。展開一行會顯示每個組件的子雜湊值——源代碼、依賴項、環境變量、項目和目標設置、Info.plist、權限、頭文件等——以便你精確定位兩次運行之間發生漂移的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕來導出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次運行之間的 JSON 是確認測試目標雜湊值漂移時哪個輸入發生更改的最快方法。
