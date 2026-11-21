---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你第一個 GitHub Actions job：連接 GitHub，將 runs-on 指向 Tuist profile，然後喺儀表板監控進度。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

喺集群上面執行工作，需要三個步驟：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 確保你嘅專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你嘅 GitHub 組織</.localized_link>。Tuist 會接收該組織嘅 `workflow_job` 事件，並將相符嘅工作分派到集群。如果冇呢個連接，工作就唔會送到你嘅 Runner。
2. **將 `runs-on` 指向 Tuist 設定檔。** 每個啟用嘅帳戶一開始就有兩個即用嘅<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 同 `macos`。使用 `tuist-` 前綴來引用佢哋：

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
   > macOS Runner 映像包含單一版本嘅 Xcode，Tuist 會根據設定檔喺工作開始之前選擇。如果你正從 GitHub 託管嘅 Runner 遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具同動作來切換 Xcode 版本嘅步驟。嗰啲步驟通常引用專為 GitHub 託管映像設計嘅 Xcode 安裝，並可能喺 Tuist Runners 上失敗。
   >
   > 要使用另一個 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇一個包含該版本嘅設定檔</.localized_link>並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 同 `swift` 隨後就會使用設定檔所選嘅 Xcode，無需喺工作流程中進行額外設定。

3. **推送並觀察。** 工作會被排隊、由 Runner 領取，並串流回你 Tuist 儀表板嘅 **Runners** 部分，你可以喺嗰度追蹤日誌、步驟同機器指標。

## 快取卷宗 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷宗</.localized_link>喺工作之間保留 Xcode、模組同 Gradle 快取以及其他目錄。喺 checkout 之後、使用佢哋嘅命令之前加入。

授予工作 `id-token: write` 權限，以便其快取卷宗同已快取嘅 checkout 喺啟動時立即掛載。如果冇呢個權限，Runner 會等待 GitHub 報告佢正在執行邊個工作，而 GitHub 遲報嘅工作會以空快取啟動。使用 OpenID Connect 登入 Tuist 嘅工作流程已經授予咗呢個權限。

```yaml
permissions:
  contents: read
  id-token: write
```
