---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · 入門指南 · 教學指南 · Tuist",
  "description": "將現有的 Xcode 專案連接到 Tuist，以使用 Xcode 編譯快取、建構與測試分析、套件大小追蹤及預覽連結，無須採用專案生成功能。"
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

如果你想保留 `.xcodeproj` 或 `.xcworkspace` 的原狀，同時引入 Tuist 的功能而無需採用專案生成，請遵循此路徑。以下每個章節都會先說明目前缺少的部分，然後引導你使用填補該空缺的功能。

## 必要條件

- macOS 搭配 **Xcode 26 或更高版本**（編譯快取和現代化洞察功能依賴於此）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到你的工作區時，選擇 **整合 `<YourApp>`**，然後在瀏覽器中進行驗證並選擇應擁有該專案的帳戶。Tuist 會在根目錄寫入一個 `Tuist.swift`，以固定專案控制代碼，讓你的團隊成員和 CI 共用相同的連線。提交它。

如果你透過程式碼代理程式或腳本驅動此操作，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式表單：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下所有內容均為可選且獨立。

## Xcode 編譯快取

Xcode 26 內建每個檔案的編譯快取，但其儲存位置位於機器的 `DerivedData` 內。全新建置會在本地填充它；團隊成員和 CI 執行器會從頭開始重新建置，因為他們看不到該儲存區。

`tuist setup cache` 將 Xcode 的編譯快取指向共用的 Tuist 快取網路。任何開發人員機器或 CI 執行中的命中，都會使其他建置相同修訂版本的機器受益。

```bash
tuist setup cache
```

在 Xcode 中建置。清除 Derived Data，在第二台機器或 CI 執行器上再次建置。第二次建置所需時間大幅縮短，且 Xcode 的建置報告會顯示編譯快取命中。

## 建置洞察

Xcode 會在日誌和建置報告中記錄每個目標的建置持續時間。兩者都不會跨執行或跨機器進行匯總。落在某個 PR 中的建置時間回歸通常只表現為整體 CI 變慢，沒有明顯信號指出是哪個目標導致或何時發生。

建置洞察會記錄每次建置的持續時間和階段計時，以便在儀表板上看到趨勢。這是方案中的一行後動作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 在 **Provide build settings from** 下，選擇你的應用程式目標。
4. 貼上符合你安裝 Tuist 方式的行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的方案腳本不會繼承你 shell 的 `PATH`，因此無法自行找到 mise 的 shim。上面的 Mise 行透過其絕對路徑呼叫 mise，並要求它從 `$SRCROOT` 載入設定，以便選擇你專案中固定的版本。
5. 建置一次。建置會在幾秒鐘內出現在儀表板的 **Builds** 分頁中。

## 測試洞察

Xcode 的測試日誌會列出每次執行的每個測試結果。它不會匯總你實際需要的跨執行信號：測試失敗的頻率、上週變慢了多少、是否僅在某些模擬器上失敗。一個在十次 CI 執行中從可靠變得不穩定的測試，看起來與一次不幸的執行相同。

測試洞察會記錄每次測試的結果和持續時間，並關聯跨執行的結果。慢速測試、失敗和不穩定測試會顯示在儀表板的 **Tests** 分頁中。

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
5. 執行測試動作一次。結果會出現在儀表板的 **Tests** 分頁中。

## 套件洞察

IPA 的安裝和下載大小會隨著每個新增的資產和連結的符號而變化。Xcode 會在 **Product → Show Archive** 中按需報告大小，而不是作為一系列報告。新增大型資產的 PR 在合併佇列中與其他 PR 無異。

套件洞察會記錄每次分析建置的安裝和下載大小，並且當超過每個分支的閾值時可以使 PR 檢查失敗。在建置步驟之後立即將此添加到你的 CI 中：

```bash
tuist inspect bundle App.ipa
```

在儀表板上開啟 **Bundle insights** 以查看趨勢並設定閾值。

## 預覽

TestFlight 在每次分享時都會增加建置和審查的往返過程。直接發送已簽名的 `.ipa` 需要收件人的 UDID 在配置描述檔中。對於只想嘗試當前分支的設計人員或 QA 來說，這兩者都不方便。

Previews 將建置轉換為可分享的連結，只需一個命令即可在模擬器或裝置上運行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

發送連結。收件人可以使用 `tuist run <url>` 或 Tuist macOS 應用程式運行它。

## 帶領團隊一起加入

快取和洞察會隨著連接到專案的人數增加而產生複合效應。從儀表板的帳戶設定邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而不需要每個人執行 `tuist auth login`。

## 下一步

如果你超越了這個階段，最大的一步是使用 Tuist 生成的專案。這是一個真正的改變（目標在 Swift 清單中描述，而不是 `.xcodeproj`），但它能解鎖模組快取和選擇性測試。在 <.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南中有端到端的涵蓋。
