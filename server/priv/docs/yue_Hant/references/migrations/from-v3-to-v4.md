---
{
  "title": "由 v3 升級至 v4",
  "titleTemplate": ":title · 遷移指南 · 參考資料 · Tuist",
  "description": "本頁說明如何將 Tuist CLI 由版本 3 遷移至版本 4。"
}
---
# 由 Tuist v3 升級至 v4 {#from-tuist-v3-to-v4}

隨著 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) 發佈，我們藉此機會引入一些破壞性變更，相信長遠而言會讓專案更易用和維護。本文概述將專案從 Tuist 3 升級至 Tuist 4 所需作出的變更。

### 不再透過 `tuistenv` 管理版本 {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安裝腳本會安裝一個名為 `tuistenv` 的工具，並在安裝時重新命名為 `tuist`。該工具負責安裝和啟用 Tuist 版本，確保跨環境的一致性。為縮減 Tuist 的功能範圍，我們決定棄用 `tuistenv`，轉而採用 [Mise](https://mise.jdx.dev/)；這是一款能完成相同工作但更靈活、且可跨不同工具使用的工具。如果你曾使用 `tuistenv`，你需要執行 `curl -Ls https://uninstall.tuist.io | bash` 來解除安裝目前的 Tuist 版本，然後以你選擇的方式重新安裝。我們強烈建議使用 Mise，因為它能夠在各環境中以確定性的方式安裝和啟用版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **在 CI 環境與 Xcode 專案中使用 Mise**
>
> 如果你決定全面採用 Mise 帶來的一致性，我們建議查閱有關如何在 [CI 環境](https://mise.jdx.dev/continuous-integration.html) 和 [Xcode 專案](https://mise.jdx.dev/ide-integration.html#xcode) 中使用 Mise 的文件。


> [!NOTE]
> **支援 Homebrew**
>
> 請注意，你仍可使用 Homebrew 安裝 Tuist；Homebrew 是 macOS 上流行的套件管理器。你可以在 <.localized_link href="/guides/install-tuist#alternative-homebrew">安裝指南</.localized_link> 中找到如何使用 Homebrew 安裝 Tuist 的說明。


### 移除 `init` 建構函式，改為使用 `ProjectDescription` 模型 {#dropped-init-constructors-from-projectdescription-models}

為提升 API 的可讀性與表達力，我們決定從所有 `ProjectDescription` 模型中移除 `init` 建構函式。現在每個模型都提供靜態建構函式，可用來建立模型實例。如果你曾使用 `init` 建構函式，你需要更新專案以改用靜態建構函式。

> [!TIP]
> **命名慣例**
>
> 我們遵循的命名慣例是使用模型名稱作為靜態建構函式的名稱。例如，`Target` 模型的靜態建構函式為 `Target.target`。


### 將 `--no-cache` 重新命名為 `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由於 `--no-cache` 旗標語意含糊，我們決定將其重新命名為 `--no-binary-cache`，以明確指出它指的是二進制快取。如果你曾使用 `--no-cache` 旗標，你需要更新專案以改用 `--no-binary-cache` 旗標。

### 將 `tuist fetch` 重新命名為 `tuist install` {#renamed-tuist-fetch-to-tuist-install}

我們將 `tuist fetch` 指令重新命名為 `tuist install`，以符合業界慣例。如果你曾使用 `tuist fetch` 指令，你需要更新專案以改用 `tuist install` 指令。

### [採用 `Package.swift` 作為依賴項目的 DSL](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，你可以在 `Dependencies.swift` 檔案中定義依賴項目。這種專有格式導致 [Dependabot](https://github.com/dependabot) 或 [Renovatebot](https://github.com/renovatebot/renovate) 等工具無法自動更新依賴項目。此外，它也為使用者帶來不必要的間接層。因此，我們決定採用 `Package.swift` 作為在 Tuist 中定義依賴項目的唯一方式。如果你曾使用 `Dependencies.swift` 檔案，你需要將 `Tuist/Dependencies.swift` 的內容移至根目錄下的 `Package.swift`，並使用 `#if TUIST` 指示詞來設定整合。你可以在此閱讀更多關於如何整合 Swift Package 依賴項目的資訊：<.localized_link href="/guides/features/projects/dependencies#swift-packages">here</.localized_link>

### 將 `tuist cache warm` 重新命名為 `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

為簡潔起見，我們決定將 `tuist cache warm` 指令重新命名為 `tuist cache`。如果你曾使用 `tuist cache warm` 指令，你需要更新專案以改用 `tuist cache` 指令。


### 將 `tuist cache print-hashes` 重新命名為 `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我們決定將 `tuist cache print-hashes` 指令重新命名為 `tuist cache --print-hashes`，以明確指出它是 `tuist cache` 指令的旗標。如果你曾使用 `tuist cache print-hashes` 指令，你需要更新專案以改用 `tuist cache --print-hashes` 旗標。

### 移除快取設定檔 {#removed-caching-profiles}

在 Tuist 4 之前，你可以在 `Tuist/Config.swift` 中定義包含快取設定的快取設定檔。我們決定移除此功能，因為在生成過程中使用與生成專案時不同的設定檔可能會造成混淆。此外，這可能導致使用者使用除錯設定檔來建置應用程式的發行版本，從而產生預期外的結果。取而代之，我們引入了 `--configuration` 選項，你可在使用它來指定生成專案時想要使用的設定。如果你曾使用快取設定檔，你需要更新專案以改用 `--configuration` 選項。

### 移除 `--skip-cache`，改以參數控制 {#removed-skipcache-in-favor-of-arguments}

我們從 `generate` 指令中移除了 `--skip-cache` 旗標，改為透過參數控制哪些目標應略過二進制快取。如果你曾使用 `--skip-cache` 旗標，你需要更新專案以改用參數。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [移除簽章功能](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

簽章已由社群工具如 [Fastlane](https://fastlane.tools/) 及 Xcode 本身解決，而且它們做得更好。我們認為簽章對 Tuist 而言屬於延伸目標，最好專注於專案的核心功能。如果你曾使用 Tuist 的簽章功能（即在儲存庫中加密憑證與描述檔，並在生成時安裝到正確位置），你可能需要在專案生成前執行的腳本中複製該邏輯。具體而言：
  - 一個腳本，使用儲存在檔案系統或環境變數中的金鑰解密憑證與描述檔，並將憑證安裝到钥匙串，將佈建描述檔安裝到目錄 `~/Library/MobileDevice/Provisioning\ Profiles`。
  - 一個腳本，可取得現有的描述檔與憑證並對其加密。

> [!TIP]
> **簽章需求**
>
> 簽章需要正確的憑證存在於钥匙串中，且佈建描述檔存在於目錄 `~/Library/MobileDevice/Provisioning\ Profiles` 中。你可以使用 `security` 命令列工具將憑證安裝到钥匙串，並使用 `cp` 命令將佈建描述檔複製到正確的目錄。


### 不再透過 `Dependencies.swift` 整合 Carthage {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，Carthage 依賴項可以在 `Dependencies.swift` 檔案中定義，用戶可以透過執行 `tuist fetch` 來取得。我們也認為這對 Tuist 而言屬於延伸目標，特別是考慮到 Swift Package Manager 將成為管理依賴項的首選方式。如果你曾使用 Carthage 依賴項，你需要直接使用 `Carthage` 將預編譯的 frameworks 和 XCFrameworks 拉取到 Carthage 的標準目錄，然後在你的目標中使用 `TargetDependency.xcframework` 和 `TargetDependency.framework` 案例來引用這些二進制檔。

> [!NOTE]
> **仍然支援 Carthage**
>
> 有些用戶誤以為我們放棄了對 Carthage 的支援。事實並非如此。Tuist 與 Carthage 輸出之間的契約是針對系統儲存的 frameworks 和 XCFrameworks。唯一改變的是負責取得依賴項的一方。以前是 Tuist 透過 Carthage，現在則是 Carthage。


### 移除 `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，你可以使用 `TargetDependency.packagePlugin` 案例來定義套件外掛程式依賴項。在看到 Swift Package Manager 引入新的套件類型後，我們決定迭代 API，使其更靈活且具備未來相容性。如果你曾使用 `TargetDependency.packagePlugin`，你需要改用 `TargetDependency.package`，並將你想使用的套件類型作為參數傳遞。

### [移除已棄用的 API](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我們移除了在 Tuist 3 中被標記為已棄用的 API。如果你曾使用任何已棄用的 API，你需要更新專案以使用新的 API。
