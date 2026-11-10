---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將現有的 Xcode 專案連接至 Tuist，以使用 Xcode 編譯快取、建構與測試洞察、套件大小追蹤及預覽連結，無須採用專案產生功能。"
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

如果你想保持 `.xcodeproj` 或 `.xcworkspace` 原封不動，同時引入 Tuist 的功能而無須採用專案生成，請遵循此路徑。以下每個章節會先說明目前缺少的部分，再引導你使用填補該空缺的功能。

## 必要條件

- macOS 搭配 **Xcode 26 或以上版本**（編譯快取與現代化洞察功能依賴此版本）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到你的工作區時，選擇 **整合 `<YourApp>`**，然後在瀏覽器中進行驗證並選擇應擁有該專案的帳戶。Tuist 會在根目錄寫入一個 `Tuist.swift`，將專案句柄固定下來，讓你的隊友和 CI 共用同一個連線。將其提交。

如果你從程式碼代理或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下內容皆為可選且獨立。

## Xcode 編譯快取

Xcode 26 內建每個檔案的編譯快取，但其儲存位置位於機器的 `DerivedData` 內。乾淨建構會在本地填充它；隊友和 CI 執行器因為看不到該儲存位置，所以會從頭重新建構。

`tuist setup cache` 將 Xcode 的編譯快取指向共用的 Tuist 快取網路。任何開發者機器或 CI 執行中的命中，都會讓其他建構相同修訂版本的機器受益。

```bash
tuist setup cache
```

此命令會列印 Xcode 使用共用快取所需的建構設定。它不會編輯你的專案，因此請將它們加入專案的建構設定或 `.xcconfig` 檔案，詳情請參閱 <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">設定 Xcode 建構設定</.localized_link>。

在 Xcode 中建構，然後在第二台機器或 CI 執行器上建構相同的修訂版本。第二次建構只需一小段時間即可完成，且 Xcode 的建構報告會顯示編譯快取命中。

## 建構洞察

Xcode 會在記錄和建構報告中記錄每個目標的建構持續時間。兩者都不會跨執行或跨機器匯總。出現在單一 PR 中的建構時間回歸通常只會表現為整體 CI 變慢，沒有明顯信號指出是哪個目標造成或何時發生。

建構洞察會記錄每次建構的持續時間和階段計時，讓趨勢在儀表板上可見。這是在你的 scheme 上的一行後續動作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 在 **Provide build settings from** 下方，選擇你的應用程式目標。
4. 貼上符合你安裝 Tuist 方式的那一行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的 scheme 腳本不會繼承你 shell 的 `PATH`，因此 mise 的 shim 無法自行找到。上述 Mise 行透過絕對路徑呼叫 mise，並要求它從 `$SRCROOT` 載入設定，以便選擇你專案中固定的版本。
5. 建構一次。建構會在幾秒內出現在儀表板的 **Builds** 分頁。

## 測試洞察

Xcode 的測試記錄會逐次列出每個測試的結果。它不會匯總你真正需要的跨執行信號：測試失敗的頻率、上週變慢了多少、是否只在某些模擬器上失敗。一個在十次 CI 執行中從可靠逐漸變得不穩定的測試，看起來與單次不幸的執行無異。

測試洞察會記錄每個測試的結果和持續時間，並關聯跨執行的結果。緩慢測試、失敗和不穩定測試會顯示在儀表板的 **Tests** 分頁。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 你的應用程式目標。
4. 貼上： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 執行測試動作一次。結果會出現在儀表板的 **Tests** 分頁。

## 套件洞察

IPA 的安裝和下載大小會隨著每個新增的資產和連結的符號而變化。Xcode 會在 **Product → Show Archive** 中按需報告大小，而非作為一系列數據。在合併佇列中，新增大型資產的 PR 與其他任何 PR 無異。

套件洞察會記錄每次分析建構的安裝和下載大小，並在超過每分支閾值時使 PR 檢查失敗。在建構步驟之後立即將此添加到你的 CI：

```bash
tuist inspect bundle App.ipa
```

在儀表板上開啟 **Bundle insights** 以查看趨勢並設定閾值。

## 預覽

TestFlight 在每次分享時都會增加建構和審查的往返過程。直接發送已簽名的 `.ipa` 需要在配置描述檔中包含接收者的 UDID。對於只想嘗試當前分支的設計人員或 QA 來說，這兩者都不方便。

Previews 將建構轉換為可分享的連結，只需一個命令即可在模擬器或裝置上運行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

發送連結。接收者可以使用 `tuist run <url>` 或 Tuist macOS 應用程式運行它。

## 帶團隊一起加入

快取和洞察的效益會隨著連接至專案的人數增加而累積。從儀表板的帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

## 下一步

如果你超越了這個階段，最大的一步是採用 Tuist 產生的專案。這是一個實質的改變（目標在 Swift 清單中描述，而非 `.xcodeproj`），但它能解鎖模組快取和選擇性測試。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南涵蓋了端到端的完整流程。
