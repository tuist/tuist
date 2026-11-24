---
{
  "title": "生成的 Xcode 項目",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 選擇性測試，只執行受你最新改動影響的 Xcode 及生成項目測試，讓持續整合在數秒內提供反饋。"
}
---
# 已生成嘅 Xcode 專案 {#generated-xcode-project}

隨著專案規模擴大，每次推送都執行所有測試會難以擴展。Tuist 嘅選擇性測試只會執行自上次成功測試執行以來目標有變更嘅測試，基於 Tuist 嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

要對你嘅 <.localized_link href="/guides/features/projects">已生成專案</.localized_link> 進行選擇性測試，請使用 `tuist test` 指令。該指令會以同 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同嘅方式為你的專案 <.localized_link href="/guides/features/projects/hashing">計算雜湊值</.localized_link>，並在成功時儲存這些雜湊值，以便在未來執行時判斷哪些內容已變更。在未來嘅執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，只執行自上次成功測試執行以來有變更嘅測試。

`tuist test` 直接與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，利用本地或遠端儲存中嘅二進制檔案來縮短執行測試套件時嘅建置時間。將選擇性測試與模組快取結合，可以大幅減少在 CI 上執行測試所需嘅時間。

如果你嘅測試只針對模擬器，請傳遞 `--destination simulator`，這樣 `tuist test` 就只會使用和下載快取二進制檔案中嘅模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。選擇性測試嘅雜湊值對於每個 `--destination` 值都係相同嘅。

## 分離建置和測試任務 {#separate-build-and-test-jobs}

選擇性測試支援分離嘅建置和測試任務。在建置任務中執行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置產出嘅產品一起儲存。該圖表攜帶選擇性測試所需嘅雜湊值，因此測試任務無需重新生成專案或解析 Swift Package 依賴關係來確定要執行哪些目標。

Tuist 在 `--build-only` 期間會將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` bundle 內部。
- 位於衍生資料嘅 `Build/Products/` 目錄下每個 `.xctestrun` 檔案旁邊。

將任一輸出與建置產品一起快取，並在測試任務中將相同路徑傳遞給 `--without-building`。兩種形式均可運作：

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

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置任務使用普通嘅 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會退回到重新生成專案，以便仍能計算受影響嘅目標。這種回退需要在測試任務上解析 Swift Package 依賴關係，因此請先執行 `tuist install` 或在任務之間快取 `Tuist/.build`。

該圖表反映咗建置時嘅原始碼樹狀結構。請針對與建置任務相同嘅 commit 執行測試任務——如果兩者之間嘅原始碼發生偏移，雜湊值將不再與原始碼匹配，選擇性測試可能會跳過實際上會在新原始碼上失敗嘅測試。

### 我應該使用哪個標誌？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 係兩種不同嘅 Xcode 輸出格式，它們在可移植性和流程便利性之間取得平衡：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新流程。** 這是一個自包含嘅目錄：建置好嘅 `.xctest` 二進制檔案及其 `.xctestrun` 檔案都位於其中，路徑相對於 bundle 根目錄，因此無論移動到哪裡都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已經有一個圍繞衍生資料構建嘅流程，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 頂部寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置嘅測試 bundle。在另一個任務中重用意味著保持 `Build/Products/` 中嘅路徑完整無損。

如果你從頭開始，首選 `-testProductsPath`。如果你將 Tuist 接入一個已經快取咗衍生資料嘅現有流程，只要建置任務通過 `tuist test --build-only` 運行，`-xctestrun` 就能獲得相同嘅快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些標誌，並通過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組與檔案層級粒度**
>
> 由於無法檢測測試與原始碼之間嘅代碼內依賴關係，默認選擇性測試嘅最大粒度係目標層級。[覆蓋率策略](#coverage-based-test-selection) 將其縮小到單個測試。因此，我們建議保持目標小而專注，以最大化選擇性測試嘅效益。


## 基於覆蓋率嘅測試選擇 {#coverage-based-test-selection}

> [!NOTE]
> **早期訪問**
>
> 基於覆蓋率嘅測試選擇處於早期訪問階段。請聯繫我們以為你嘅帳戶啟用此功能。在啟用之前，該策略嘅行為與默認選擇性測試相同。

默認情況下，選擇性測試會跳過雜湊值已通過嘅整個測試目標。`.coverage()` 策略更進一步：在剩餘嘅測試目標中，它還會跳過那些在 earlier run 中代碼覆蓋率未涵蓋你變更所涉及任何檔案嘅測試。它適用於 XCTest 和 XCUITest 測試，以及配置好嘅 [Swift Testing](#swift-testing) 測試套件。在 `Tuist.swift` 中啟用：

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

- **覆蓋率上傳。** Tuist 根據 earlier runs 上傳嘅覆蓋率來選擇測試，因此如果 manifest 將 `.coverage()` 設置為 `upload: false`，`tuist test` 將無法加載。
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 或更高版本**，並由你嘅測試目標 [連結](#linking-testcoverageattribution)。它記錄每個測試執行咗哪些檔案，並跳過 Tuist 未選擇嘅測試。沒有它嘅目標只會像默認情況下一樣被整體跳過。
- **足夠頻繁嘅完整測試執行。** 使用 `tuist test --no-selective-testing` 嘅執行會執行每個測試並成為基準。選擇性執行會與其 commit 歷史中同一平台上最近嘅一次執行進行比較，如果沒有基準則不應用覆蓋率。在哪裡以及多久執行一次取決於你團隊嘅工作方式，例如在你嘅默認分支嘅每個 commit、每晚或發佈分支上。我們推薦默認分支：在那裡進行完整執行也可以在變更發布之前捕捉到覆蓋率無法看到嘅問題，例如測試依賴嘅 fixture 或服務。

啟用該策略後，`tuist test` 會跳過雜湊值已通過嘅目標，然後詢問 Tuist 你嘅變更會影響剩餘目標中嘅哪些測試。沒有受影響測試嘅目標不會被建置。新測試、上次失敗嘅測試、位於已變更測試檔案中嘅測試，以及沒有記錄覆蓋率嘅測試始終會執行。

有時覆蓋率不會被應用，輸出會說明原因：雜湊值未通過嘅目標中嘅每個測試都會執行，同默認選擇性測試一樣。當同一平台上沒有最近嘅基準、變更涉及超過 5,000 個檔案，或者可能影響任何測試嘅檔案（例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）發生變更時，就會出現這種情況。要執行每個測試，請傳遞 `--no-selective-testing`。

> [!NOTE]
> **測試覆蓋率**
>
> 讀取單次執行報告嘅覆蓋率工具（包括 Xcode 自帶嘅）假設整個測試套件都已執行，因此選擇性執行嘅報告會省略它跳過嘅測試。Tuist 嘅 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 反而會從 earlier run 繼承被跳過測試目標嘅覆蓋率，使用它在每次執行時記錄嘅 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標級別覆蓋率</.localized_link>。

### 連結 TestCoverageAttribution {#linking-testcoverageattribution}

將該包添加到 `Tuist/Package.swift`，並鎖定到其次要版本，因為 0.x 次要版本可能會改變它記錄嘅內容：

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

然後將其添加到您嘅測試目標中，切勿添加到應用程式目標：

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

Tuist 默認將包連結為靜態框架。僅包含 XCTest 嘅目標不會引用包中嘅任何內容，因此連結器會將其丟棄，連同記錄和跳過功能一起丟棄。要么將 `-ObjC` 添加到測試目標嘅 `OTHER_LDFLAGS`，要么在 `Tuist/Package.swift` 中動態連結該包：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing 沒有庫可以加入嘅觀察 API，因此其測試需要在它們嘅套件上使用 TestCoverageAttribution 嘅 `.coverageAttribution` 特性。該特性適用於嵌套在具有該特性嘅套件中嘅套件。沒有該特性嘅套件中嘅測試不會記錄每個測試嘅覆蓋率，因此每當其目標運行時它們都會運行。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **測試不得重疊。** Swift Testing 默認並行運行進程中嘅測試，而覆蓋率計數器無法區分同時運行嘅測試，因此這些測試不會記錄自己嘅覆蓋率並且始終運行。`.serialized` 僅對套件自身嘅測試進行排序，因此只有當目標只有一個套件時才足夠。XCTest 不需要任何東西：並行測試在各自嘅進程中運行每個測試克隆。
- **按測試目標關閉並行化。** Xcode 將設置應用於每個測試目標，因此你只能為你希望逐個測試選擇嘅目標關閉它，而方案中嘅其他目標繼續並行運行。不需要單獨嘅方案。在可測試目標上設置它，`.testableTarget(target: "CheckoutTests", parallelization: .disabled)`，這也會在沒有克隆嘅情況下運行該目標嘅 XCTest 測試。Tuist 生成嘅方案從項目嘅 `testingOptions` 獲取此設置，除非它們包含 `.parallelizable` 或 `.swiftTestingOnlyParallelizable`，否則為關閉狀態。將 `-parallel-testing-enabled YES` 或 `NO` 傳遞給 `tuist test` 會覆蓋該次運行中每個目標嘅設置。
- **跳過需要 Swift 6.3 (Xcode 26.4) 或更高版本。** 該特性會取消 Tuist 未選擇嘅測試並將它們報告為已跳過。在較早版本中，測試仍然記錄覆蓋率，但 Tuist 未選擇嘅測試仍然會運行。

### 始終運行嘅測試 {#tests-that-always-run}

覆蓋率只能看到測試執行嘅代碼。如果測試嘅實際輸入是 fixtures、資源、網絡或環境，即使沒有任何被覆蓋嘅代碼發生變化，測試也可能失敗。將其標記為不可跳過，即使 Tuist 未選擇它，它也會運行：

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

它僅適用於運行嘅測試目標。雜湊值已通過嘅目標，或者 Tuist 未選擇其中任何測試嘅目標，會被整體跳過且從不啟動，因此其不可跳過嘅測試也不會運行。

參閱 [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) 以了解所有選項。

### 檢查選擇 {#inspecting-a-selection}

測試執行嘅「選擇性測試」標籤頁顯示覆蓋率選擇咗什麼以及原因。相同嘅數據可以從 CLI 獲取，使用 `--json` 進行腳本編寫，並通過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 提供給代理：

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

當覆蓋率未被應用時，測試仍然計為基於覆蓋率嘅選擇：它們嘅原因說明咗覆蓋率無法決定嘅原因，例如 `tracked_file_changed`。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git forge 集成**
>
> 要獲得自動嘅 pull/merge request 評論，請將你嘅 <.localized_link href="/guides/server/accounts-and-projects">Tuist 項目</.localized_link> 與 Git forge 集成：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


一旦你嘅 Tuist 項目與你嘅 Git 平台（例如 [GitHub](https://github.com)）連接，並且你開始將 `tuist test` 作為 CI 工作流嘅一部分使用，Tuist 將直接在你嘅 pull/merge requests 中發布評論，包括哪些測試已運行以及哪些已跳過：![帶有 Tuist Preview 鏈接嘅 GitHub app 評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當以前緩存嘅測試目標顯示為未命中時，測試執行頁面上嘅 **選擇性測試** 標籤頁允許你深入查看產生雜湊值嘅輸入。展開一行會顯示每個組件嘅子雜湊值 — 源代碼、依賴項、環境變量、項目和目標設置、Info.plist、權限、頭文件等 — 以便你可以準確找出兩次運行之間發生漂移嘅輸入。

使用選擇性測試卡片頂部嘅 **複製為 JSON** 按鈕來導出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次運行之間嘅 JSON 是確認測試目標雜湊值漂移時哪個輸入發生變化嘅最快方法。
