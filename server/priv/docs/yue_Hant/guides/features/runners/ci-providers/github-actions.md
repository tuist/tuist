---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅第一個 GitHub Actions 工作：連接 GitHub，將 runs-on 指向 Tuist 設定檔，然後喺儀表板中監控。"
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

喺集群上執行作業需要三個改動：連接 GitHub、將 `runs-on` 指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，然後推送。

1. **連接 GitHub。** 確保你嘅專案已<.localized_link href="/guides/integrations/gitforge/github">連接到你嘅 GitHub 組織</.localized_link>。Tuist 會接收該組織嘅 `workflow_job` 事件，並將相符嘅作業分派到集群。如果冇呢個連接，就冇任何作業會到達你嘅執行器。
2. **將 `runs-on` 指向 Tuist 設定檔。** 每個已啟用嘅帳戶一開始就有兩個即用嘅<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 同 `macos`。使用 `tuist-` 前綴來引用佢哋：

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **用執行器設定檔選擇 Xcode**
   >
   > macOS 執行器映像包含單一版本嘅 Xcode，Tuist 會根據設定檔喺作業開始之前選擇佢。如果你正從 GitHub 託管嘅執行器遷移，請移除使用 `xcode-select --switch`（或 `xcode-select -s`）或其他工具同動作來切換 Xcode 版本嘅步驟。呢啲步驟通常引用專為 GitHub 託管映像設計嘅 Xcode 安裝，可能會喺 Tuist Runners 上失敗。
   >
   > 要使用另一個 Xcode 版本，請<.localized_link href="/guides/features/runners/profiles#creating-a-profile">建立或選擇一個包含該版本嘅設定檔</.localized_link>並更新 `runs-on`，例如 `runs-on: tuist-xcode-26-4`。`xcodebuild`、`xcrun` 同 `swift` 就會使用設定檔所選嘅 Xcode，無需喺工作流程中進行任何其他設定。

3. **推送並監察。** 作業會被排入佇列、由執行器領取，並串流返回到你 Tuist 儀表板嘅 **執行器** 部分，你可以喺嗰度追蹤佢嘅日誌、步驟同機器指標。

## 快取卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷</.localized_link>喺作業之間保留 Xcode、模組同 Gradle 快取以及其他目錄。喺檢出之後、使用佢哋嘅命令之前加入佢哋。

授予作業 `id-token: write` 權限，以便佢嘅快取卷同已快取嘅檢出喺開始時立即掛載。如果冇呢個權限，執行器會等待 GitHub 報告佢正在運行邊個作業，而 GitHub 遲報嘅作業會以空快取啟動。使用 OpenID Connect 登入 Tuist 嘅工作流程已經授予咗呢個權限。

```yaml
permissions:
  contents: read
  id-token: write
```
