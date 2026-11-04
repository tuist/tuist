---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，僅執行受最新變更影響的 Xcode 與產生之專案測試，讓持續整合在數秒內提供回饋。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project}

隨著專案規模擴大，測試數量也會增加。長久以來，在每次 PR 或推送到 `main` 時執行所有測試需要數十秒。但這種做法無法擴充到團隊可能擁有的數千個測試。

在 CI 的每次測試執行中，你很可能會不論變更內容而重新執行所有測試。Tuist 的選擇性測試能大幅加速測試執行，只執行自上次成功測試執行以來已變更的測試，依據我們的 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

若要在你的 <.localized_link href="/guides/features/projects">產生的專案</.localized_link> 中選擇性地執行測試，請使用 `tuist test` 指令。該指令會以與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同的方式為你的專案進行 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，並在成功時持久化這些雜湊值，以便在未來的執行中判斷哪些內容已變更。在未來的執行中，`tuist test` 會透明地使用這些雜湊值來篩選測試，只執行自上次成功測試執行以來已變更的測試。

`tuist test` 直接與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，盡可能使用本機或遠端儲存空間中的二進位檔，以改善執行測試套件時的建置時間。將選擇性測試與模組快取結合，可以大幅減少在 CI 上執行測試所需的時間。

如果你的測試僅針對模擬器，請傳遞 `--destination simulator`，讓 `tuist test` 僅使用和下載快取二進位檔的模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。選擇性測試的雜湊值對於每個 `--destination` 值都相同。

## 分離建置與測試工作 {#separate-build-and-test-jobs}

選擇性測試支援分離的建置與測試工作。在建置工作中執行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 檔案與建置輸出的產物一起持久化。該圖表攜帶選擇性測試所需的雜湊值，因此測試工作無需重新產生專案或解析 Swift Package 相依性即可判斷要執行哪些目標。

Tuist 在 `--build-only` 期間將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` 套件內。
- 位於衍生資料的 `Build/Products/` 目錄下，緊鄰每個 `.xctestrun` 檔案。

將任一輸出與建置產物一起快取，並在測試工作中將相同路徑傳遞給 `--without-building`。兩種形式皆可行：

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
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

當 Tuist 無法在輸入旁邊找到該圖表時（例如，當建置工作使用一般的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會退回到重新產生專案，以便仍能計算受影響的目標。該回退需要在測試工作上解析 Swift Package 相依性，因此請先執行 `tuist install` 或在工作之間快取 `Tuist/.build`。

該圖表反映建置時的來源樹狀結構。請針對與建置工作相同的提交執行測試工作——如果兩者之間的來源發生偏移，雜湊值將會過時，選擇性測試可能會跳過實際上會在較新來源上失敗的測試。

### 我應該使用哪個旗標？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是兩種不同的 Xcode 輸出格式，它們在可移植性與管線便利性之間取捨：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新管線。** 這是一個自包含目錄：建置完成的 `.xctest` 二進位檔及其 `.xctestrun` 檔案位於其中，路徑相對於套件根目錄，因此無論移至何處都能保持有效。這也是擁有選擇性測試快速路徑最久的格式，因此是使用最廣泛的路徑。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有圍繞衍生資料建立的管線，請使用此選項。** `xcodebuild build-for-testing` 預設會在 `<derivedData>/Build/Products/` 的頂層寫入一個 `.xctestrun`，並將其指向位於該樹狀結構其他位置的測試套件。在另一個工作中重複使用它意味著保持 `Build/Products/` 中的路徑完整。

如果你從頭開始，請優先使用 `-testProductsPath`。如果你將 Tuist 連線到已快取衍生資料的現有管線，只要建置工作透過 `tuist test --build-only` 執行，`-xctestrun` 現在就能獲得相同的快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳引數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會略過這些旗標，並透過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組與檔案層級粒度**
>
> 由於無法偵測測試與來源之間的程式碼內相依性，選擇性測試的最大粒度為目標層級。因此，我們建議保持目標小而專注，以最大化選擇性測試的效益。


> [!NOTE]
> **測試涵蓋率**
>
> 讀取單一執行報告的涵蓋率工具（包括 Xcode）假設整個測試套件都已執行，因此選擇性執行的報告會遺漏其跳過的測試。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">程式碼涵蓋率</.localized_link> 會改為從较早的執行中延續已跳過測試目標的涵蓋率，使用它在每次執行時記錄的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標層級涵蓋率</.localized_link>。


## Pull/Merge Request 註解 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台整合**
>
> 若要取得自動的 Pull/Merge Request 註解，請將你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。


將你的 Tuist 專案與 [GitHub](https://github.com) 等 Git 平台連接，並開始在 CI 工作流程中使用 `tuist test` 後，Tuist 會直接在你的拉取／合併請求中發布評論，說明哪些測試已執行、哪些已略過：![包含 Tuist Preview 連結的 GitHub 應用程式評論](/images/guides/features/selective-testing/github-app-comment.png)


## 在儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前快取的測試目標顯示為未命中時，測試執行頁面上的 **選擇性測試** 分頁可讓你深入檢視產生雜湊值的輸入。展開一列會顯示每個元件的子雜湊值——來源、相依性、環境變數、專案與目標設定、Info.plist、權限、標頭檔等——以便你找出在執行之間發生偏移的輸入。

使用選擇性測試卡片頂部的 **複製為 JSON** 按鈕，匯出每個選擇性測試目標及其雜湊值和子雜湊值。比較兩次執行之間的 JSON 是確認測試目標雜湊值偏移時哪個輸入已變更的最快方法。
