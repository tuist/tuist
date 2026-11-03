---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · 快速入門 · 指南 · Tuist",
  "description": "將現有的 Xcode 專案與 Tuist 整合，即可使用 Xcode 編譯快取、建置與測試洞察、套件大小追蹤及預覽連結，無需採用專案產生功能。"
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

如果你想保留現有的 `.xcodeproj` 或 `.xcworkspace` 原封不動，同時引入 Tuist 的功能而不採用專案生成，請遵循此路徑。以下每個章節都會先說明目前缺少的部分，再引導你使用能填補該空缺的功能。

## 前置需求

- macOS 搭配 **Xcode 26 或更新版本**（編譯快取與現代化洞察功能皆依賴此版本）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到你的工作區時，選擇 **整合 `<YourApp>`**，接著在瀏覽器中完成驗證，並選擇應擁有此專案的帳號。Tuist 會在根目錄寫入一個 `Tuist.swift`，將專案控制代碼固定下來，讓你的團隊成員與 CI 共用相同的連線。請將其提交。

如果你是由程式碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下所有步驟皆為選用且彼此獨立。

## Xcode 編譯快取

Xcode 26 內建了以檔案為單位的編譯快取，但其存放區位於機器的 `DerivedData` 內。乾淨建置會在本地填充該快取；由於團隊成員與 CI 執行器看不到該存放區，因此會從頭重新建置。

`tuist setup cache` 會將 Xcode 的編譯快取指向共用的 Tuist 快取網路。任何開發者機器或 CI 執行中的快取命中，都能讓其他建置相同修訂版本的機器受益。

```bash
tuist setup cache
```

在 Xcode 中建置。清除 Derived Data，並在第二台機器或 CI 執行器上再次建置。第二次建置所需的時間大幅縮短，且 Xcode 的建置報告會顯示編譯快取的命中情況。

## 建置洞察

Xcode 會在記錄檔與建置報告中記錄每個目標的建置持續時間，但這些資料不會跨執行或跨機器匯總。出現在單一 PR 中的建置時間回退，通常只表現為整體 CI 變慢，而沒有明確訊號指出是哪個目標造成問題或何時發生。

建置洞察會記錄每次建置的持續時間與階段計時，讓趨勢在儀表板上清晰可見。這只需在你的 Scheme 中加入一行後置動作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 在 **Provide build settings from** 下方，選擇你的 App 目標。
4. 貼上符合你安裝 Tuist 方式的指令： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的 Scheme 腳本不會繼承你 Shell 的 `PATH`，因此無法自動找到 mise 的 shim。上述 Mise 指令透過絕對路徑呼叫 mise，並要求它從 `$SRCROOT` 載入設定，以便選取你專案中固定的版本。
5. 建置一次。該建置會在幾秒內出現在儀表板的 **Builds** 分頁中。

## 測試洞察

Xcode 的測試記錄會逐次列出每次執行的個別測試結果。它不會匯總你真正需要的跨執行訊號：測試失敗的頻率、上週變慢了多少、是否僅在特定模擬器上失敗。一個在十次 CI 執行中從可靠逐漸變成不穩定的測試，看起來與單次運氣不佳的執行並無二致。

測試洞察會記錄每次測試的結果與持續時間，並關聯跨執行的結果。緩慢的測試、失敗與不穩定測試會顯示在儀表板的 **Tests** 分頁中。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 你的 App 目標。
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

IPA 的安裝與下載大小會隨著每次加入的資源與連結的符號而改變。Xcode 僅在 **Product → Show Archive** 中按需報告大小，而非作為一系列趨勢呈現。在合併佇列中，加入大型資源的 PR 與其他 PR 難以區分。

套件洞察會記錄每次分析建置的安裝與下載大小，並在超過每分支門檻時使 PR 檢查失敗。在建置步驟之後立即將此行加入你的 CI：

```bash
tuist inspect bundle App.ipa
```

在儀表板上開啟 **Bundle insights** 以查看趨勢並設定門檻。

## 預覽

TestFlight 在每次分享時都會增加建置與審查的往返流程。直接傳送已簽署的 `.ipa` 則需要在佈建描述檔中包含接收者的 UDID。對於只想嘗試目前分支的設計人員或 QA 來說，這兩種方式都不夠方便。

Previews 能將建置轉換為可分享的連結，只需一個指令即可在模擬器或裝置上執行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

傳送該連結。接收者可透過 `tuist run <url>` 或 Tuist macOS App 執行它。

## 邀請團隊成員加入

快取與洞察的效益會隨著連接到專案的人數增加而累積。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

## 下一步

若你超越此階段，最重要的一步是採用 Tuist 產生的專案。這是一項實質變更（目標以 Swift 資訊清單描述，而非 `.xcodeproj`），但正是這項變更能解鎖模組快取與選擇性測試。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南提供端到端的完整說明。
