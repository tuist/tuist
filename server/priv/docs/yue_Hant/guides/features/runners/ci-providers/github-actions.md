---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你第一個 GitHub Actions 工作：連接 GitHub，將 runs-on 指向 Tuist 設定檔，然後喺儀表板中監察。"
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **僅限 GitHub 組織**
>
> Tuist Runners 只會執行由 GitHub 組織（而非個人帳戶）擁有的儲存庫中的工作。

要在叢集上執行工作，需要進行三項變更：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 請確保你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的工作分派到叢集。如果沒有此連接，工作就無法到達你的 Runner。
2. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用的帳戶都預設提供兩個即用型<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。使用 `tuist-` 前綴來引用它們：

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
   > macOS Runner 映像檔包含單一版本的 Xcode，Tuist 會根據設定檔在工作開始前選取該版本。如果你正從 GitHub 託管的 Runner 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具和動作來切換 Xcode 版本的步驟。這些步驟通常引用 GitHub 託管映像檔特有的 Xcode 安裝，在 Tuist Runners 上可能會失敗。
   >
   > 如需使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇</.localized_link>包含該版本的設定檔，並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後會使用設定檔所選的 Xcode，無需在工作流程中進行額外設定。

3. **推送並觀察。** 工作會被放入佇列、由 Runner 領取，並串流回 Tuist 儀表板的 **Runners** 區段，你可以在那裡追蹤其日誌、步驟和機器指標。

## 快取卷冊 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後以及在使用它們的命令之前加入這些卷冊。

授予工作 `id-token: write` 權限，以便其快取卷冊和快取的 checkout 能在啟動時立即掛載。如果沒有此權限，Runner 會等待 GitHub 報告正在執行的工作，而 GitHub 延遲報告的工作會以空快取啟動。使用 OpenID Connect 登入 Tuist 的工作流程已自動授予此權限。

```yaml
permissions:
  contents: read
  id-token: write
```
