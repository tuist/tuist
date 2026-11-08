---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅第一個 GitHub Actions job：連接 GitHub，將 runs-on 指向 Tuist profile，然後喺儀表板監察進度。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

要在 Tuist 執行環境上運行工作，只需三個步驟：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 請確保你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派到執行環境。如果沒有此連接，任何工作都無法到達你的 Runner。
2. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用的帳戶預設都有兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前綴來引用它們：

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
   > macOS Runner 映像檔包含單一版本的 Xcode，Tuist 會根據設定檔在工作開始前選取該版本。如果你正從 GitHub 託管的 Runner 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具和 Action 來切換 Xcode 版本的步驟。這些步驟通常引用 GitHub 託管映像檔特有的 Xcode 安裝路徑，在 Tuist Runners 上可能會失敗。
   >
   > 若要使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇一個包含該版本的設定檔</.localized_link>並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後便會使用設定檔中選取的 Xcode，無需在工作流程中進行額外設定。

3. **推送並觀察。** 工作會被放入佇列、由 Runner 領取，並串流回 Tuist 儀表板的 **Runners** 區段，你可以在那裡追蹤其日誌、步驟和機器指標。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在不同工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後、在使用這些目錄的命令之前加入它們。

授予工作 `id-token: write` 權限，以便其快取磁碟區和已快取的 checkout 能在啟動時立即掛載。若無此權限，Runner 會等待 GitHub 回報正在執行的工作，而 GitHub 延遲回報的工作將會以空快取啟動。使用 OpenID Connect 登入 Tuist 的工作流程已自動授予此權限。

```yaml
permissions:
  contents: read
  id-token: write
```
