---
{
  "title": "最佳實踐",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解使用 Tuist 生成專案的最佳實踐。"
}
---
# 最佳實踐 {#best-practices}

多年來與不同團隊和項目合作，我們總結出一套在使用 Tuist 和 Xcode 項目時建議遵循的最佳實踐。這些實踐並非強制性，但能幫助你以更易於維護和擴展的方式構建項目結構。

## Xcode {#xcode}

### 不推薦的模式 {#discouraged-patterns}

#### 用於模擬遠端環境的配置 {#configurations-to-model-remote-environments}

許多組織使用構建配置來模擬不同的遠端環境（例如 `Debug-Production` 或 `Release-Canary`），但這種方法有一些缺點：

- **不一致：** 如果依賴圖中存在配置不一致的情況，構建系統可能會為某些目標使用錯誤的配置。
- **複雜性：** 項目最終可能會包含一長串難以理解和維護的本地配置及遠端環境。

構建配置旨在體現不同的構建設置，而項目很少需要除了 `Debug` 和 `Release` 之外的其他配置。模擬不同環境的需求可以通過其他方式實現：

- **在 Debug 構建中：** 你可以將開發階段應可訪問的所有配置（例如端點）包含在應用中，並在運行時切換。切換可以通過 Scheme 啟動環境變量或應用內的 UI 進行。
- **在 Release 構建中：** 對於發布版本，你可以只包含該發布構建所綁定的配置，並通過編譯器指令排除切換配置的運行時邏輯。

> [!NOTE]
> **非標準配置**
>
> 雖然 Tuist 支持非標準配置，並且相比原生 Xcode 項目更易於管理，但如果配置在整個依賴圖中不一致，你將會收到警告。這有助於確保構建的可靠性並防止與配置相關的問題。


## 生成的項目

### 可構建文件夾

Tuist 4.62.0 增加了對 **可構建文件夾**（Xcode 的同步組）的支持，這是 Xcode 16 引入的一項功能，旨在減少合併衝突。

雖然 Tuist 的通配符模式（例如 `Sources/**/*.swift`）已經消除了生成項目中的合併衝突，但可構建文件夾提供了額外的好處：

- **自動同步**：你的項目結構會與文件系統保持同步——添加或刪除文件時無需重新生成
- **對 AI 友好的工作流程**：編碼助手和代理可以修改你的代碼庫而不會觸發項目重新生成
- **更簡單的配置**：定義文件夾路徑而不是管理明確的文件列表

我們建議採用可構建文件夾，而不是傳統的 `Target.sources` 和 `Target.resources` 屬性，以獲得更流暢的開發體驗。

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 依賴關係

#### 在 CI 上強制使用已解析的版本

在 CI 上安裝 Swift Package Manager 依賴項時，我們建議使用 `--force-resolved-versions` 標誌以確保確定性構建：

```bash
tuist install --force-resolved-versions
```

此標誌確保依賴項使用 `Package.resolved` 中鎖定的確切版本進行解析，從而消除由依賴項解析中的非確定性引起的問題。這在 CI 上尤為重要，因為可重複構建至關重要。

#### 在 GitHub Actions 上緩存依賴項安裝 {#dependency-cache-volumes}

對於生成的項目，使用 [tuist/install](https://github.com/tuist/install) 安裝 `Package.resolved` 中鎖定的依賴項並在多次運行之間緩存它們。它會在 Tuist Runners 上自動使用 <.localized_link href="/guides/features/runners/cache-volumes">緩存卷</.localized_link>，在其他 Runner 上使用 GitHub 的緩存。

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

對於子目錄中的項目，傳遞相對於 checkout 的路徑：

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

查看 [action 參考文檔](https://github.com/tuist/install#usage) 以獲取更多選項。

### 代理編碼和工作樹 {#agentic-coding-and-worktrees}

編碼代理和人類貢獻者越來越多地並行工作：開發人員保持一個工作樹打開以審查他們的功能，而一個或多個代理在兄弟工作樹中的自己的分支上迭代。一些項目選擇可以使這一過程更加順暢。

#### 使用可構建文件夾進行代理驅動的編輯 {#worktrees-buildable-folders}

當代理添加或刪除文件時，任何依賴 `Project.swift` 中文件列表的內容都需要在項目再次構建之前執行 `tuist generate`。[可構建文件夾](#buildable-folders)將該責任下推至 Xcode 的同步組，因此文件樹編輯不再觸發重新生成。

將其與 `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link>結合使用，這教會代理 Tuist 項目的日常工作流程。

#### 不要按工作樹隔離緩存 {#worktrees-shared-cache}

Tuist 遵循 <.localized_link href="/cli/directories">XDG 基本目錄規範</.localized_link>，因此默認情況下同一台機器上的每個工作樹共享 `~/.cache/tuist` 和 `~/.local/state/tuist`。這正是你想要的：在一個工作樹中編譯的輔助工具、在另一個工作樹中下載的插件以及由第三個工作樹拉取的模塊緩存二進制文件都是可重用的。

跨工作樹的並發 `tuist` 調用可以安全地並行運行。除非你特別需要隔離，否則避免將 `TUIST_XDG_CACHE_HOME` 指向工作樹本地路徑；這樣做會迫使每個工作樹重新預熱輔助工具、插件和二進制文件。

#### 保持每個工作樹的 SwiftPM 臨時文件獨立 {#worktrees-swiftpm-scratch}

Swift Package Manager 有自己的路徑控制。`--scratch-path` 是可變的工作狀態，默認為 `.build`，而 `--cache-path` 是共享緩存目錄。當多個工作樹處於活動狀態時，不應將這兩條路徑同等對待。

Tuist 的預設 `tuist install` 行為已經將 SwiftPM 臨時文件保留在包目錄下，因此每個工作樹都有自己的 `.build`。保持這種隔離。單個共享的 SwiftPM 臨時文件目錄可能會混合來自不相關分支的 checkout、構建中間件、插件、宏和鎖定文件。

如果你通過 `tuist install -- ...` 或通過 `Tuist.swift` 中的 `installOptions` 傳遞 SwiftPM 參數，在希望更快獲取依賴項時共享 `--cache-path`，但讓 `--scratch-path` 保持未設置或指向工作樹本地目錄：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

如果緩存路徑需要根據 Xcode、Swift 工具鏈或平台而變化，請使用包裝器或 CI 環境變量。避免將共享的 `--scratch-path` 提交到存儲庫。

如果只有一個工作樹中的依賴狀態看起來損壞，請刪除該工作樹的 `.build` 目錄並再次運行 `tuist install`。如果跨工作樹的共享 SwiftPM 緩存本身看起來可疑，請在重新安裝依賴項之前使用 `swift package purge-cache`。

#### 依靠模塊緩存 {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">模塊緩存</.localized_link> 使並行工作樹變得可行。因為 Tuist 為每個目標計算一個確定性的 <.localized_link href="/guides/features/projects/hashing">哈希</.localized_link>，所以指向共享大部分歷史記錄的分支的兩個工作樹會命中相同的二進制文件。在 CI 上每次提交到 `main` 時運行 `tuist cache`；在本地，每個工作樹中的 `tuist generate` 會從緩存中提取它可以提取的任何內容，並且只構建你的分支實際更改的內容。

如果工作樹在你預期快取命中時回退到源代碼構建，請遵循 <.localized_link href="/guides/features/projects/hashing#debugging">哈希調試步驟</.localized_link>；非確定性哈希（通常由項目中的絕對路徑引起）是最常見的原因，並且在比較兩個工作樹時會明顯顯示出來。

#### 使用註冊表加速 Swift Package 解析 {#worktrees-registry}

每個工作樹獨立解析 Swift 包。在具有大型依賴關係圖的項目中，這會快速累積。切換到 <.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> 可以避免重新克隆 git 歷史記錄，並將解析時間從幾分鐘減少到幾秒鐘。

#### 讓代理訪問項目洞察 {#worktrees-mcp}

一旦構建和測試在許多工作樹中運行，代理最有用的事情就是推理 *哪些* 運行出現了回歸，哪些測試是不穩定的，或者捆綁大小如何變化。Tuist 通過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服務器</.localized_link> 和 <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> 包公開這些數據。每個工作流選擇一個並堅持使用；將兩者混合用於同一任務往往會導致代理行為不一致。
