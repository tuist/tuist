---
{
  "title": "已生成嘅 Xcode 專案",
  "titleTemplate": ":title · 選擇性測試 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Selective Testing，只執行受你最近改動影響嘅 Xcode 同已生成專案測試，令持續整合喺幾秒內提供回饋。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project}

隨著你嘅專案增長，測試數量亦會增加。好長一段時間以來，每次 PR 或推送至 `main` 時運行所有測試都要花幾十秒。但呢個方案無法擴展到你團隊可能擁有嘅數千個測試。

喺 CI 上每次執行測試時，你很可能會重新運行所有測試，而唔理變更內容。Tuist 嘅選擇性測試透過只運行自上次成功測試執行以來有變更嘅測試，基於我哋嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>，幫你大幅加快測試運行速度。

要同你嘅 <.localized_link href="/guides/features/projects">已產生專案</.localized_link> 一齊選擇性運行測試，請使用 `tuist test` 指令。該指令會以同 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 相同嘅方式為你的專案進行 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，成功後會持久化這些雜湊值，以確定未來運行中哪些內容發生咗變化。喺未來運行中，`tuist test` 會透明地使用雜湊值來篩選測試，只運行自上次成功測試執行以來有變更嘅測試。

`tuist test` 直接同 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 整合，利用本地或遠端儲存中嘅二進制檔案來改善運行測試套件時嘅構建時間。將選擇性測試同模組快取結合，可以大幅減少喺 CI 上運行測試所需嘅時間。

如果你嘅測試只針對模擬器，請傳遞 `--destination simulator`，令 `tuist test` 只使用並下載快取二進制檔案嘅模擬器切片。請參閱 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目的地選擇</.localized_link>。選擇性測試嘅雜湊值對於每個 `--destination` 值都係相同嘅。

## 分開構建同測試任務 {#separate-build-and-test-jobs}

選擇性測試支援分開嘅構建同測試任務。喺構建任務中運行 `tuist test --build-only`，讓 Tuist 能夠將 `selective-testing-graph.json` 文件同構建產物一齊持久化。該圖表攜帶選擇性測試所需嘅雜湊值，因此測試任務無需重新產生專案或解析 Swift Package 依賴項來確定要運行哪些目標。

Tuist 喺 `--build-only` 期間會將圖表寫入兩個位置：

- 當你傳遞 `-testProductsPath` 時，位於 `.xctestproducts` bundle 內部。
- 位於衍生數據 `Build/Products/` 目錄下每個 `.xctestrun` 文件旁邊。

將任一輸出同構建產物一齊快取，並將相同路徑傳遞給測試任務中嘅 `--without-building`。兩種形式都有效：

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

當 Tuist 無法喺輸入旁邊找到該圖表時（例如，當構建任務使用普通嘅 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它會回退到重新產生專案，以便仍然可以計算受影響嘅目標。該回退需要喺測試任務上解析 Swift Package 依賴項，因此請先運行 `tuist install` 或喺任務之間快取 `Tuist/.build`。

圖表反映咗構建時嘅源代碼樹狀態。請針對同構建任務相同嘅 commit 運行測試任務 — 如果兩者之間嘅源代碼發生偏移，雜湊值就會過時，選擇性測試可能會跳過實際上會喺新源代碼上失敗嘅測試。

### 我應該使用哪個標誌？ {#which-flag-should-i-use}

`.xctestrun` 同 `.xctestproducts` 係兩種不同嘅 Xcode 輸出格式，佢哋喺可移植性同流水線便利性之間作出權衡：

- **`-testProductsPath` (`.xctestproducts`) — 建議用於新流水線。** 這是一個自包含目錄：構建好嘅 `.xctest` 二進制檔案同佢哋嘅 `.xctestrun` 文件都存放喺裡面，路徑相對於 bundle 根目錄，因此無論移動到哪裡都保持有效。這亦係擁有選擇性測試快速路徑最久嘅格式，因此係經過最多驗證嘅路徑。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已經有圍繞衍生數據構建嘅流水線，請使用此選項。** `xcodebuild build-for-testing` 預設情況下會喺 `<derivedData>/Build/Products/` 頂部寫入一個 `.xctestrun`，並指向位於該樹其他位置嘅測試 bundle。喺另一個任務中重用佢意味著要保持 `Build/Products/` 中嘅路徑完整無損。

如果你從頭開始，請優先使用 `-testProductsPath`。如果你將 Tuist 接入已經快取咗衍生數據嘅現有流水線，只要構建任務通過 `tuist test --build-only` 運行，`-xctestrun` 現在就會獲得相同嘅快速路徑。

任一輸入模式都與 `-workspace`/`-project`/`-scheme` 互斥，因此當透傳參數包含 `-xctestrun` 或 `-testProductsPath` 時，Tuist 會跳過這些標誌，並通過 `-only-testing` 轉發所選目標。

> [!WARNING]
> **模組級別與文件級別粒度**
>
> 由於無法檢測測試同源代碼之間嘅代碼內依賴關係，選擇性測試嘅最大粒度係喺目標級別。因此，我哋建議保持你嘅目標小而專注，以最大化選擇性測試嘅效益。


> [!NOTE]
> **測試覆蓋率**
>
> 讀取單次運行報告嘅覆蓋率工具（包括 Xcode 自帶嘅）假設整個測試套件都已運行，因此選擇性運行嘅報告會省略被跳過嘅測試。Tuist 嘅 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代碼覆蓋率</.localized_link> 會改用之前運行中記錄嘅 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目標級別覆蓋率</.localized_link>，將被跳過測試目標嘅覆蓋率延續下來。


## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台集成**
>
> 要獲取自動嘅 Pull/Merge Request 評論，請將你嘅 <.localized_link href="/guides/server/accounts-and-projects">Tuist 專案</.localized_link> 同 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。


一旦你嘅 Tuist 專案同如 [GitHub](https://github.com) 等 Git 平台連接，並且你開始將 `tuist test` 作為 CI 工作流嘅一部分使用，Tuist 就會直接喺你嘅 Pull/Merge Request 中發布評論，包括哪些測試已運行以及哪些被跳過：![帶有 Tuist Preview 鏈接嘅 GitHub app 評論](/images/guides/features/selective-testing/github-app-comment.png)


## 喺儀表板上調查未命中 {#investigating-misses-on-the-dashboard}

當先前快取嘅測試目標顯示為未命中時，測試運行頁面上嘅 **選擇性測試** 標籤頁讓你深入查看產生雜湊值嘅輸入。展開一行會顯示每個組件嘅子雜湊值 — 源代碼、依賴項、環境變量、專案同目標設置、Info.plist、權限、頭文件等 — 以便你準確找出喺兩次運行之間發生偏移嘅輸入。

使用選擇性測試卡片頂部嘅 **複製為 JSON** 按鈕，導出每個選擇性測試目標及其雜湊值同子雜湊值。比較兩次運行之間嘅 JSON 係確認測試目標雜湊值偏移時哪個輸入發生變化嘅最快方法。
