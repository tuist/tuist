---
{
  "title": "Xcode 專案",
  "titleTemplate": ":title · 入門指南 · 教學文件 · Tuist",
  "description": "將現有 Xcode 專案連接至 Tuist，即可使用 Xcode 編譯快取、建置與測試分析、套件大小追蹤及預覽連結，無須採用專案產生功能。"
}
---
# Xcode 專案 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

如果你想保留現有嘅 `.xcodeproj` 或 `.xcworkspace` 不變，同時引入 Tuist 嘅功能而唔需要採用專案生成，就依循呢個路徑。下面每個部分都會先指出目前缺少咩，再帶你了解填補空缺嘅功能。

## 先決條件

- macOS 配備 **Xcode 26 或更高版本**（編譯快取同現代化洞察功能都依賴佢）。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

喺儲存庫根目錄執行 `tuist init`。當 Tuist 偵測到你嘅工作區時，選擇 **整合 `<YourApp>`**，然後喺瀏覽器進行身份驗證，並揀選應該擁有該專案嘅帳戶。Tuist 會喺根目錄寫入一個 `Tuist.swift`，鎖定專案句柄，令你嘅隊友同 CI 共用同一個連接。提交佢。

如果你係透過編碼代理程式或腳本嚟驅動呢個過程，請先執行 `tuist auth login`（瀏覽器流程會等你按 Enter），然後使用非互動式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下內容均為可選且獨立。

## Xcode 編譯快取

Xcode 26 附帶逐檔案編譯快取，但其儲存位置位於機器嘅 `DerivedData` 內。乾淨建構會喺本地填充佢；但隊友同 CI 執行器因為睇唔到該儲存位置，所以要重新從頭建構。

`tuist setup cache` 將 Xcode 嘅編譯快取指向共享嘅 Tuist 快取網絡。任何開發者機器或 CI 運行中嘅命中，都會令其他建構相同版本嘅機器受益。

```bash
tuist setup cache
```

喺 Xcode 中進行建構。清除 Derived Data，然後喺第二部機器或 CI 執行器上再次建構。第二次建構所需時間大幅縮短，而且 Xcode 嘅建構報告會顯示編譯快取命中情況。

## 建構洞察

Xcode 會喺日誌同建構報告中記錄每個目標嘅建構持續時間。兩者都冇跨運行或跨機器匯總。如果某個 PR 出現建構時間回歸，通常只會表現為整體 CI 變慢，而冇明顯信號指出係邊個目標導致或者何時發生。

建構洞察會記錄每次建構嘅持續時間同階段計時，令趨勢喺儀表板上清晰可見。這只需要喺你嘅 Scheme 中添加一行後置動作：

1. 喺 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展開 **Build → Post-actions**，點擊 **+**，選擇 **New Run Script Action**。
3. 喺 **Provide build settings from** 下，揀選你嘅應用程式目標。
4. 貼上符合你安裝 Tuist 方式嘅一行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 嘅 Scheme 腳本唔會繼承你 Shell 嘅 `PATH`，所以 mise 嘅 shim 無法自動找到。上面嘅 Mise 行通過絕對路徑調用 mise，並要求佢從 `$SRCROOT` 載入配置，以便揀選你專案中鎖定嘅版本。
5. 建構一次。建構結果會喺幾秒內出現喺儀表板嘅 **Builds** 標籤頁。

## 測試洞察

Xcode 嘅測試日誌會逐次運行列出每個測試嘅結果。它並冇匯總你真正需要嘅跨運行信號：測試失敗頻率、上週變慢咗幾多、是否只喺特定模擬器上失敗。一個喺十次 CI 運行中從可靠逐漸變成不穩定嘅測試，看起來同單次不幸運行冇分別。

測試洞察會記錄每個測試嘅結果同持續時間，並關聯跨運行嘅結果。慢速測試、失敗同不穩定測試會顯示喺儀表板嘅 **Tests** 標籤頁。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 你嘅應用程式目標。
4. 貼上： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 運行測試動作一次。結果會顯示喺儀表板嘅 **Tests** 標籤頁。

## 套件洞察

IPA 嘅安裝同下載大小會隨著每個添加嘅資源同連結嘅符號而變化。Xcode 只係喺 **Product → Show Archive** 中按需報告大小，而唔係作為一系列數據。喺合併隊列中，添加大資源嘅 PR 同其他 PR 冇分別。

套件洞察會記錄每次分析建構嘅安裝同下載大小，並且當超過每個分支嘅閾值時，可以令 PR 檢查失敗。喺你嘅 CI 中建構步驟之後立即添加此行：

```bash
tuist inspect bundle App.ipa
```

喺儀表板上打開 **Bundle insights** 以查看趨勢並配置閾值。

## 預覽

TestFlight 每次分享都需要經歷建構同審查嘅往返過程。直接發送簽名嘅 `.ipa` 需要收件人嘅 UDID 包含喺配置描述文件中。對於只想嘗試當前分支嘅設計師或 QA 來說，兩者都唔方便。

Previews 將建構轉換為可分享嘅連結，只需一條命令即可喺模擬器或設備上運行：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

發送連結。收件人可以通過 `tuist run <url>` 或 Tuist macOS 應用程式運行佢。

## 帶領團隊一起使用

快取同洞察會隨著連接項目嘅人數增加而累積效果。從儀表板嘅帳戶設定邀請你嘅隊友加入組織，並設置 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而唔係每人執行一次 `tuist auth login`。

## 下一步

如果你超越咗呢個階段，最大嘅一步係使用 Tuist 生成嘅項目。這是一個真正嘅改變（目標喺 Swift 清單中描述，而唔係 `.xcodeproj`），但佢解鎖咗模組快取同選擇性測試。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 指南提供咗端到端嘅涵蓋。
