---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上執行你的第一個 GitHub Actions 工作：連接 GitHub、將 runs-on 指向 Tuist 設定檔，並在儀表板中監控執行狀況。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯絡我們，以請求開啟你的帳戶存取權限。

在叢集上執行工作需進行三項變更：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **請求存取權限。** 測試期間，Runners 僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)並提供你想要啟用的帳戶。
2. **連接 GitHub。** 請確保你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接至你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派至叢集。若未建立此連接，工作將無法送達你的 runners。
3. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用的帳戶都預設提供兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。請使用 `tuist-` 前綴來引用它們：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **透過 runner 設定檔選擇 Xcode**
   >
   > macOS runner 映像檔包含單一版本的 Xcode，Tuist 會在作業開始前依據設定檔進行選擇。若你從 GitHub 託管的 runners 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具與動作來切換 Xcode 版本的步驟。這些步驟通常參考 GitHub 託管映像檔中特定的 Xcode 安裝路徑，在 Tuist Runners 上可能會失敗。
   >
   > 若要使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇包含該版本的設定檔</.localized_link>，並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後將使用設定檔所選的 Xcode，无需在工作流程中進行額外設定。

4. **推送並觀察。** 工作會被排入佇列、由 runner 領取，並串流回傳至 Tuist 儀表板的 **Runners** 區段，你可以在那裡追蹤其日誌、步驟和機器指標。

## 快取卷冊 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>在不同工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後、在使用這些目錄的命令之前加入它們。
