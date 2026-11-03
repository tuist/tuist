---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "喺 Tuist Runners 執行你第一個 GitHub Actions job：連接 GitHub，將 runs-on 指向 Tuist profile，然後喺 dashboard 監察進度。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，以申請你帳戶的存取權限。

在叢集上執行工作需要三個步驟：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **申請存取權限。** 測試期間 Runner 僅限邀請。[聯絡我們](mailto:contact@tuist.dev)並提供你想啟用的帳戶。
2. **連接 GitHub。** 確保你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派到叢集。沒有此連接，工作就無法送達你的 Runner。
3. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用的帳戶一開始都有兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前綴來引用它們：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **透過 Runner 設定檔選擇 Xcode**
   >
   > macOS Runner 映像包含單一版本的 Xcode，Tuist 會根據設定檔在工作開始前選取該版本。如果你正從 GitHub 託管的 Runner 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具和動作來切換 Xcode 版本的步驟。這些步驟通常引用 GitHub 託管映像特有的 Xcode 安裝路徑，在 Tuist Runners 上可能會失敗。
   >
   > 要使用另一個 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇包含該版本的設定檔</.localized_link>，並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後會使用設定檔所選的 Xcode，工作流程中無需額外設定。

4. **推送並觀察。** 工作會被放入佇列、由 Runner 領取，並串流回 Tuist 儀表板的**Runners**區段，你可以在那裡追蹤其日誌、步驟和機器指標。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後、在使用它們的命令之前加入這些磁碟區。
