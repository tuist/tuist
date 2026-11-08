---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將現有的 Xcode 專案連接至 Tuist，即可享有 Xcode 編譯快取、建置與測試洞察、套件大小追蹤以及預覽連結，無需採用專案生成。"
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

若你想保留現有的 `.xcodeproj` 或 `.xcworkspace` 不變，並在不採用專案生成的情況下引入 Tuist 的功能，請遵循此路徑。以下每個章節都會先說明目前缺少的功能，再逐步引導你使用能填補該空缺的功能。

## 必要條件

- macOS 搭配 **Xcode 26 或更新版本**（編譯快取與現代化洞察功能皆依賴此版本）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到你的工作區時，選擇 **整合 `<YourApp>`**，接著在瀏覽器中進行驗證，並選擇應擁有該專案的帳號。Tuist 會在根目錄寫入一個 `Tuist.swift`，將專案控制代碼固定下來，讓你的團隊成員與 CI 共用相同的連線。請提交此檔案。

若你是透過程式碼代理程式或腳本來執行，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下內容均為可選且彼此獨立。

## Xcode 編譯快取

Xcode 26 內建了以檔案為單位的編譯快取，但其儲存位置位於機器的 `DerivedData` 內。全新建置會在本地填充該快取；但團隊成員與 CI 執行器因為看不到該儲存區，所以會從頭重新建置。

`tuist setup cache` 會將 Xcode 的編譯快取指向共用的 Tuist 快取網路。任何開發者機器或 CI 執行中的快取命中，都能讓其他建置相同修訂版本的機器受益。

```bash
tuist setup cache
```

此指令會印出 Xcode 使用共用快取所需的建置設定。它不會編輯你的專案，因此請將這些設定加入專案的建置設定或 `.xcconfig` 檔案中，詳情請參閱 <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">設定 Xcode 建置設定</.localized_link>。

在 Xcode 中建置，然後在第二台機器或 CI 執行器上建置相同的修訂版本。第二次建置只需極短時間即可完成，且 Xcode 的建置報告會顯示編譯快取的命中情況。

## 建置洞察

Xcode 會在記錄檔與建置報告中記錄每個目標的建置持續時間。但這些數據並未跨執行或跨機器進行彙總。導致建置時間回歸的問題若出現在某個 PR 中，通常只會體現為整體 CI 變慢，而沒有明顯訊號指出是哪個目標造成問題或發生時間。

建置洞察會記錄每次建置的持續時間與階段耗時，讓趨勢能在儀表板上清晰可見。這只需在你的 Scheme 中加入一行後置動作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 在 **Provide build settings from** 下方，選擇你的 App 目標。
4. 貼上符合你安裝 Tuist 方式的指令行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的 Scheme 腳本不會繼承你 Shell 的 `PATH`，因此無法自動找到 mise 的 shim。上述 Mise 指令行透過絕對路徑呼叫 mise，並要求它從 `$SRCROOT` 載入設定，以便選用你專案中固定的版本。
5. 執行一次建置。該建置會在幾秒內出現在儀表板的 **Builds** 分頁中。

## 測試洞察

Xcode 的測試記錄會逐次列出每次執行的個別測試結果。它並未彙總你真正需要的跨執行訊號：測試失敗的頻率、上週變慢了多少、是否僅在特定模擬器上失敗。一個在十次 CI 執行中從穩定逐漸變成不穩定的測試，看起來與单次運氣不好的執行並無二致。

測試洞察會記錄每次測試的結果與持續時間，並跨執行關聯結果。緩慢的測試、失敗與不穩定情況會顯示在儀表板的 **Tests** 分頁中。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 選擇你的 App 目標。
4. 貼上： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 執行一次測試動作。結果會出現在儀表板的 **Tests** 分頁中。

## 套件洞察

IPA 的安裝與下載大小會隨著每次加入的資源與連結的符號而變化。Xcode 僅在 **Product → Show Archive** 中按需報告大小，而非作為一系列數據呈現。在合併佇列中，加入大型資源的 PR 與其他 PR 並無區別。

套件洞察會記錄每次分析建置的安裝與下載大小，並在超過每分支閾值時使 PR 檢查失敗。請在建置步驟之後立即將此指令加入你的 CI：

```bash
tuist inspect bundle App.ipa
```

在儀表板上開啟 **Bundle insights** 以查看趨勢並設定閾值。

## 預覽

TestFlight 在每次分享時都會增加建置與審查的往返流程。直接傳送簽名的 `.ipa` 則需要在佈建設定檔中包含接收者的 UDID。對於只想嘗試當前分支的設計人員或 QA 來說，這兩種方式都不夠方便。

Previews 能將建置轉換為可分享的連結，只需一個指令即可在模擬器或裝置上執行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

傳送該連結。接收者可透過 `tuist run <url>` 或 Tuist macOS App 執行它。

## 邀請團隊成員加入

快取與洞察的效益會隨著連接至專案的人數增加而累積。從儀表板的帳戶設定中邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

## 下一步

若你發現此路徑已不足以應付需求，最大的進展是採用 Tuist 產生的專案。這是一項實質的變更（目標改由 Swift 清單描述，而非 `.xcodeproj`），但正是它解鎖了模組快取與選擇性測試。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南提供了端到端的完整說明。
