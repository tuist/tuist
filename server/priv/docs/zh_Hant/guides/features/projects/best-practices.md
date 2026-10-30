---
{
  "title": "最佳實踐",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解使用 Tuist 產生之專案的最佳實踐。"
}
---
# 最佳實踐 {#best-practices}

在與不同團隊和專案合作的多年經驗中，我們總結出一套建議遵循的最佳實踐，適用於使用 Tuist 和 Xcode 專案時。這些實踐並非強制要求，但能幫助你以更易於維護和擴展的方式組織專案結構。

## Xcode {#xcode}

### 不建議的模式 {#discouraged-patterns}

#### 用於模擬遠端環境的組態 {#configurations-to-model-remote-environments}

許多組織使用建置組態來模擬不同的遠端環境（例如 `Debug-Production` 或 `Release-Canary`），但這種方法存在一些缺點：

- **不一致性：** 如果依賴圖中存在組態不一致的情況，建置系統可能會為某些目標使用錯誤的組態。
- **複雜性：** 專案最終可能包含一長串難以理解和維護的本機組態與遠端環境。

建置組態的設計目的是體現不同的建置設定，而專案通常只需要 `Debug` 和 `Release`。模擬不同環境的需求可以透過其他方式實現：

- **在 Debug 建置中：** 你可以將開發階段應可存取的所有組態（例如端點）包含在應用程式中，並在執行階段切換。切換可以透過 Scheme 啟動環境變數，或透過應用程式內的 UI 進行。
- **在 Release 建置中：** 在發布情況下，你可以只包含與發布建置綁定的組態，並透過編譯器指令不包含切換組態的執行階段邏輯。

> [!NOTE]
> **非標準組態**
>
> 雖然 Tuist 支援非標準組態，並且相比原生 Xcode 專案更易於管理，但如果組態在整個依賴圖中不一致，你將會收到警告。這有助於確保建置可靠性並防止與組態相關的問題。


## 產生的專案

### 可建置資料夾

Tuist 4.62.0 新增了對**可建置資料夾**（Xcode 的同步群組）的支援，這是 Xcode 16 引入的一項功能，旨在減少合併衝突。

雖然 Tuist 的通配符模式（例如 `Sources/**/*.swift`）已經消除了產生專案中的合併衝突，但可建置資料夾提供了額外的好處：

- **自動同步**：你的專案結構會與檔案系統保持同步—新增或移除檔案時無需重新產生
- **AI 友善的工作流程**：編碼輔助工具和代理可以修改你的程式碼庫，而不會觸發專案重新產生
- **更簡單的組態**：定義資料夾路徑，而不是管理明確的檔案清單

我們建議採用可建置資料夾，而不是傳統的 `Target.sources` 和 `Target.resources` 屬性，以獲得更流暢的開發體驗。

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

### 相依性

#### 在 CI 上強制使用已解析的版本

在 CI 上安裝 Swift Package Manager 相依性時，我們建議使用 `--force-resolved-versions` 旗標以確保決定性建置：

```bash
tuist install --force-resolved-versions
```

此旗標確保相依性使用 `Package.resolved` 中鎖定的確切版本進行解析，消除因相依性解析中的非決定性所導致的問題。這在需要可重現建置的 CI 環境中尤其重要。

#### 在 GitHub Actions 上快取相依性安裝 {#dependency-cache-volumes}

對於產生的專案，使用 [tuist/install](https://github.com/tuist/install) 安裝 `Package.resolved` 中鎖定的相依性，並在多次執行之間快取它們。它會在 Tuist Runners 上自動使用 <.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>，在其他執行器上使用 GitHub 的快取。

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

對於位於子目錄中的專案，傳遞相對於檢出目錄的路徑：

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

請參閱 [動作參考](https://github.com/tuist/install#usage) 以了解其他選項。

### 代理編碼與工作樹 {#agentic-coding-and-worktrees}

編碼代理和人類貢獻者越來越常平行工作：開發人員會為他們正在審查的功能保持一個工作樹開啟，而一個或多個代理則在兄弟工作樹中迭代它們自己的分支。一些專案選擇可以讓此過程更加順暢。

#### 使用可建置資料夾進行代理驅動的編輯 {#worktrees-buildable-folders}

當代理新增或移除檔案時，任何依賴 `Project.swift` 中檔案清單的內容都需要在專案再次建置前執行 `tuist generate`。[可建置資料夾](#buildable-folders)將該責任下放至 Xcode 的同步群組，因此檔案樹編輯不再觸發重新產生。

將其與 `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link>搭配使用，該技能教導代理 Tuist 專案的日常工作流程。

#### 不要為每個工作樹隔離快取 {#worktrees-shared-cache}

Tuist 遵循 <.localized_link href="/cli/directories">XDG 基礎目錄規範</.localized_link>，因此預設情況下，同一台機器上的每個工作樹都共用 `~/.cache/tuist` 和 `~/.local/state/tuist`。這正是你想要的：在一個工作樹中編譯的輔助工具、在另一個工作樹中下載的外掛程式，以及由第三個工作樹拉取的模組快取二進位檔都可以重複使用。

跨工作樹的並行 `tuist` 呼叫可以安全地平行執行。除非你特別需要隔離，否則避免將 `TUIST_XDG_CACHE_HOME` 指向工作樹本機路徑；這樣做會迫使每個工作樹重新暖化輔助工具、外掛程式和二進位檔。

#### 為每個工作樹保留 SwiftPM 暫存區 {#worktrees-swiftpm-scratch}

Swift Package Manager 有自己的路徑控制。`--scratch-path` 是可變的工作狀態，預設為 `.build`，而 `--cache-path` 是共用的快取目錄。當多個工作樹處於活動狀態時，不應將這兩個路徑視為相同。

Tuist 預設的 `tuist install` 行為已將 SwiftPM 暫存區保留在套件目錄下，因此每個工作樹都有自己的 `.build`。請保持這種隔離。單一共用的 SwiftPM 暫存目錄可能會混合來自不相關分支的檢出、建置中介檔案、外掛程式、巨集和鎖定檔。

如果你透過 `tuist install -- ...` 或透過 `Tuist.swift` 中的 `installOptions` 傳遞 SwiftPM 引數，在希望加快相依性擷取速度時共用 `--cache-path`，但讓 `--scratch-path` 保持未設定或指向工作樹本機目錄：

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

如果快取路徑需要因 Xcode、Swift 工具鏈或平台而異，請使用包裝器或 CI 環境變數來設定。避免將共用的 `--scratch-path` 提交至儲存庫。

如果只有一個工作樹中的相依性狀態看起來損毀，請刪除該工作樹的 `.build` 目錄並再次執行 `tuist install`。如果跨工作樹的共用 SwiftPM 快取本身看起來可疑，請在重新安裝相依性之前使用 `swift package purge-cache`。

#### 善用模組快取 {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 讓平行工作樹變得可行。因為 Tuist 會為每個目標計算確定性的 <.localized_link href="/guides/features/projects/hashing">雜湊</.localized_link>，所以指向共享大部分歷史記錄之分支的兩個工作樹將會命中相同的二進位檔。從 CI 對 `main` 的每次提交執行 `tuist cache`；在本機上，每個工作樹中的 `tuist generate` 會從快取中拉取它能取得的任何內容，並僅建置你的分支實際變更的部分。

如果工作樹在你預期快取命中時回退到原始碼建置，請遵循 <.localized_link href="/guides/features/projects/hashing#debugging">雜湊除錯步驟</.localized_link>；非確定性雜湊（通常由專案中的絕對路徑引起）是最常見的原因，且在比較兩個工作樹時會明顯出現。

#### 使用註冊表加速 Swift Package 解析 {#worktrees-registry}

每個工作樹都會獨立解析 Swift 套件。在具有大型相依性圖的專案中，這會快速累積。切換至 <.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> 可避免重新複製 git 歷史記錄，並將解析時間從幾分鐘縮短至幾秒。

#### 讓代理存取專案洞察 {#worktrees-mcp}

一旦建置和測試在許多工作樹中運行，代理最有用的事情就是推論 *哪些* 運行出現回歸、哪些測試不穩定，或套件大小如何變化。Tuist 透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link> 和 <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> 套件公開這些資料。每個工作流程選擇其中一種並堅持使用；在同一項任務中混合兩者往往會導致代理行為不一致。
