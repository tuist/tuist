---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 執行器上執行你的第一個 GitHub Actions 工作：連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在儀表板中監控。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

在叢集上執行工作需進行三項變更：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 請確認你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接至你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派至叢集。若未建立此連線，沒有任何工作能送達你的執行器。
2. **將 `runs-on` 指向 Tuist 設定檔。** 每個啟用的帳戶一開始就有兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前綴來引用它們：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **透過執行器設定檔選擇 Xcode**
   >
   > macOS 執行器映像檔包含單一版本的 Xcode，Tuist 會根據設定檔在工作開始前選取該版本。如果你從 GitHub 託管的執行器遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具與動作來切換 Xcode 版本的步驟。這些步驟通常參考 GitHub 託管映像檔特有的 Xcode 安裝，可能在 Tuist Runners 上失敗。
   >
   > 若要使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇</.localized_link>具有該版本的設定檔並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後就會使用設定檔所選取的 Xcode，無需在工作流程中進行額外設定。

3. **推送並監控。** 工作會進入佇列、由執行器領取，並串流回 Tuist 儀表板的**執行器**區段，你可以在那裡追蹤其日誌、步驟與機器指標。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在工作之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在簽出之後、在使用這些目錄的命令之前加入它們。

授予工作 `id-token: write` 權限，讓其快取磁碟區與已快取的簽出在啟動時立即掛載。若缺少此權限，執行器會等待 GitHub 回報正在執行的工作，而 GitHub 延遲回報的工作將以空白快取啟動。使用 OpenID Connect 登入 Tuist 的工作流程已自動授予此權限。

```yaml
permissions:
  contents: read
  id-token: write
```
