---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect an existing Xcode project to Tuist for the Xcode compilation cache, build and test insights, bundle-size tracking, and preview links, without adopting project generation."
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

當您希望完全保留現有的 `.xcodeproj` 或 `.xcworkspace`，並在不移植至專案生成流程的情況下引入 Tuist 的功能時，請遵循此路徑。以下每個章節都會先說明目前缺少的功能，再引導您使用能填補該空缺的功能。

## 必要條件

- 搭載 **Xcode 26 或更新版本** 的 macOS（編譯快取與現代化的洞察分析皆依賴此版本）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到您的工作區時，選擇 **整合 `<YourApp>`**，接著在瀏覽器中完成驗證，並選取應擁有該專案的帳號。Tuist 會在根目錄寫入一個 `Tuist.swift`，將專案控點固定下來，讓您的團隊成員與 CI 共用相同的連線。請將其提交至版本控制。

若您透過程式碼代理程式或腳本來執行此操作，請先執行 `tuist auth login`（瀏覽器流程會等待您按下 Enter 鍵），然後使用非互動式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下所有步驟皆為選用且彼此獨立。

## Xcode 編譯快取

Xcode 26 內建了以檔案為單位的編譯快取，但其存放區位於機器的 `DerivedData` 內。乾淨建置會在本地填充該快取；但由於團隊成員與 CI 執行器無法看見該存放區，因此必須從頭重新建置。

`tuist setup cache` 會將 Xcode 的編譯快取指向共用的 Tuist 快取網路。任何開發者機器或 CI 執行中的快取命中，都能讓其他建置相同修訂版本的機器受益。

```bash
tuist setup cache
```

在 Xcode 中建置。清除 Derived Data，然後在第二台機器或 CI 執行器上再次建置。第二次建置所需的時間大幅縮短，且 Xcode 的建置報告會顯示編譯快取的命中情況。

## 建置洞察分析

Xcode 會在日誌與建置報告中記錄每個目標的建置持續時間。這些資料並未跨執行次數或跨機器進行彙整。若某個 PR 引入了建置時間回退，通常只會體現為整體 CI 變慢，而沒有明確訊號指出是哪個目標導致問題或何時發生。

建置洞察分析會記錄每次建置的持續時間與階段耗時，讓趨勢能在儀表板上清晰可見。這只需在您的 Scheme 中加入一行後置動作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 在 **Provide build settings from** 下方，選取您的應用程式目標。
4. 貼上符合您安裝 Tuist 方式的指令： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的 Scheme 腳本不會繼承您 Shell 的 `PATH`，因此無法自動找到 mise 的 shim。上述 Mise 指令透過絕對路徑呼叫 mise，並要求它從 `$SRCROOT` 載入設定，以便選取您專案中固定的版本。
5. 執行一次建置。該建置會在幾秒內出現在儀表板的 **Builds** 分頁中。

## 測試洞察分析

Xcode 的測試日誌會逐次列出每次執行的個別測試結果。它並未彙整您真正需要的跨執行訊號：測試失敗的頻率、上週變慢了多少、是否僅在特定模擬器上失敗。一個在十次 CI 執行中從穩定逐漸變得閃爍不定的測試，看起來與單次運氣不佳的執行並無二致。

測試洞察分析會記錄每次測試的結果與持續時間，並跨執行關聯結果。緩慢的測試、失敗與閃爍問題會顯示在儀表板的 **Tests** 分頁中。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 您的應用程式目標。
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

## 套件洞察分析

IPA 的安裝與下載大小會隨著每次加入的資源與連結的符號而變化。Xcode 僅在 **Product → Show Archive** 中依需求報告大小，而非作為一系列數據呈現。在合併佇列中，新增大型資源的 PR 與其他 PR 難以區分。

套件洞察分析會記錄每次分析建置的安裝與下載大小，並可在超過每分支閾值時使 PR 檢查失敗。請在建置步驟之後立即將此指令加入您的 CI：

```bash
tuist inspect bundle App.ipa
```

在儀表板上開啟 **Bundle insights** 以查看趨勢並設定閾值。

## 預覽

TestFlight 在每次分享時都會增加建置與審查的往返流程。直接傳送已簽署的 `.ipa` 則需要在佈建描述檔中包含接收者的 UDID。對於只想嘗試當前分支的設計人員或 QA 來說，這兩種方式都不夠便利。

Previews 能將建置轉換為可分享的連結，只需一個指令即可在模擬器或裝置上執行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

傳送該連結。接收者可透過 `tuist run <url>` 或 Tuist macOS 應用程式來執行它。

## 邀請團隊加入

快取與洞察分析會隨著連接到專案的人數增加而產生複合效應。從儀表板的帳戶設定中邀請您的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

## 下一步該做什麼

如果您超越了此路徑的適用範圍，最大的步驟是採用 Tuist 產生的專案。這是一個實質的改變（目標在 Swift 清單中描述，而非 `.xcodeproj`），但這正是解鎖模組快取和選擇性測試的關鍵。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南提供了端到端的完整說明。
