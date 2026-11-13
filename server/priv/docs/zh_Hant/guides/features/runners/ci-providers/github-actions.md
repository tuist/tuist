---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · Runner · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上執行你的第一個 GitHub Actions 工作：連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在儀表板中監控。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

在叢集上執行作業需要三個步驟：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 請確認你的專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你的 GitHub 組織</.localized_link>。Tuist 會接收該組織的 `workflow_job` 事件，並將相符的作業分派至叢集。若未建立此連線，作業將無法送達你的執行器。
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
   > macOS 執行器映像檔包含單一版本的 Xcode，Tuist 會在作業開始前依據設定檔進行選擇。若你正從 GitHub 託管的執行器遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具與動作來切換 Xcode 版本的步驟。這些步驟通常參考 GitHub 託管映像檔特有的 Xcode 安裝路徑，可能在 Tuist Runners 上失敗。
   >
   > 若要使用其他 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇包含該版本的設定檔</.localized_link>並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 和 `swift` 隨後會使用設定檔所選的 Xcode，無需在工作流程中進行額外設定。

3. **推送並觀察。** 作業會進入佇列、由執行器領取，並將串流資料回傳至 Tuist 儀表板的**Runners**區段，你可以在這裡追蹤其日誌、步驟與機器指標。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在作業之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在檢出之後、在使用這些目錄的命令之前加入它們。

授予作業 `id-token: write` 權限，讓其快取磁碟區與快取的檢出內容能在作業啟動時立即掛載。若缺少此權限，執行器會等待 GitHub 回報正在執行的作業，而 GitHub 延遲回報的作業將以空白快取啟動。若工作流程已透過 OpenID Connect 登入 Tuist，則已自動授予此權限。

```yaml
permissions:
  contents: read
  id-token: write
```
