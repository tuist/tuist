---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你第一個 GitHub Actions 工作：連接 GitHub，將 runs-on 指向 Tuist 設定檔，然後喺儀表板中監控。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或於[社群 Slack](https://slack.tuist.dev)聯絡我們，以申請你帳戶的存取權限。

要在叢集上執行工作，需要三個步驟：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送程式碼。

1. **申請存取權限。** 測試期間，Runners 僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)並提供你想啟用的帳戶。
2. **連接 GitHub。** 請確保你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接至你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派至叢集。若無此連接，工作將無法送達你的 runners。
3. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用的帳戶預設提供兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前綴來引用它們：

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
   > macOS runner 映像檔包含單一版本的 Xcode，Tuist 會根據設定檔在工作開始前選取該版本。如果你正從 GitHub 託管的 runners 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具與動作來切換 Xcode 版本的步驟。這些步驟通常引用 GitHub 託管映像檔特有的 Xcode 安裝路徑，在 Tuist Runners 上可能會失敗。
   >
   > 若要使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇包含該版本的設定檔</.localized_link>，並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後會使用設定檔所選的 Xcode，無需在工作流程中進行額外設定。

4. **推送並觀察。** 工作會被排入佇列、由 runner 領取，並串流回 Tuist 儀表板的 **Runners** 區段，你可以在那裡追蹤其日誌、步驟與機器指標。

## 快取卷冊 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>在不同工作之間保留 Xcode、模組與 Gradle 快取及其他目錄。在 checkout 之後、在使用這些目錄的命令之前加入它們。

授予工作 `id-token: write` 權限，以便其快取卷冊與已快取的 checkout 能在啟動時立即掛載。若無此權限，runner 會等待 GitHub 回報正在執行的工作，而 GitHub 延遲回報的工作將會以空白快取啟動。若工作流程已透過 OpenID Connect 登入 Tuist，則已自動授予此權限。

```yaml
permissions:
  contents: read
  id-token: write
```
