---
{
  "title": "由 v3 升級至 v4",
  "titleTemplate": ":title · 遷移指南 · 參考資料 · Tuist",
  "description": "本頁說明如何將 Tuist CLI 由版本 3 遷移至版本 4。"
}
---
# 由 Tuist v3 升級至 v4 {#from-tuist-v3-to-v4}

隨著 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) 發布，我們藉此機會引入了一些破壞性變更，相信這些改動能讓專案更易於長期使用與維護。本文列出將專案從 Tuist 3 升級到 Tuist 4 時需要作出的變更。

## 不再透過 `tuistenv` 管理版本 {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安裝腳本會安裝一個名為 `tuistenv` 的工具，並在安裝時重新命名為 `tuist`。該工具負責安裝及啟用不同版本的 Tuist，確保跨環境的一致性。為縮減 Tuist 的功能範圍，我們決定棄用 `tuistenv`，轉而採用 [Mise](https://mise.jdx.dev/)；這是一款能完成相同工作但更靈活、並可跨不同工具使用的工具。如果你曾經使用 `tuistenv`，你需要執行 `curl -Ls https://uninstall.tuist.io | bash` 來解除安裝目前的 Tuist 版本，然後以你選擇的方式重新安裝。我們強烈建議使用 Mise，因為它能夠在各個環境中以確定性的方式安裝及啟用版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI 環境與 Xcode 專案中的 Mise**
>
> 如果你決定全面採用 Mise 帶來的一致性，我們建議查閱有關如何在 [CI 環境](https://mise.jdx.dev/continuous-integration.html) 及 [Xcode 專案](https://mise.jdx.dev/ide-integration.html#xcode) 中使用 Mise 的文件。


> [!NOTE]
> **支援 Homebrew**
>
> 請注意，你仍然可以使用 macOS 上流行的套件管理器 Homebrew 來安裝 Tuist。你可以在 <.localized_link href="/guides/install-tuist#recommended-homebrew">安裝指南</.localized_link> 中找到使用 Homebrew 安裝 Tuist 的說明。


## 移除 `init` 建構函式，改為使用 `ProjectDescription` 模型 {#dropped-init-constructors-from-projectdescription-models}

為提升 API 的可讀性與表達力，我們決定從所有 `ProjectDescription` 模型中移除 `init` 建構函式。現在每個模型都提供靜態建構函式，供你建立模型實例。如果你曾經使用 `init` 建構函式，你需要更新專案以改用靜態建構函式。

> [!TIP]
> **命名慣例**
>
> 我們遵循的命名慣例是以模型名稱作為靜態建構函式的名稱。例如，`Target` 模型的靜態建構函式為 `Target.target`。


## 將 `--no-cache` 重新命名為 `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由於 `--no-cache` 旗標語意含糊，我們決定將其重新命名為 `--no-binary-cache`，以明確表示它指的是二進位快取。如果你曾經使用 `--no-cache` 旗標，你需要更新專案以改用 `--no-binary-cache` 旗標。

## 將 `tuist fetch` 重新命名為 `tuist install` {#renamed-tuist-fetch-to-tuist-install}

我們將 `tuist fetch` 指令重新命名為 `tuist install`，以符合業界慣例。如果你曾經使用 `tuist fetch` 指令，你需要更新專案以改用 `tuist install` 指令。

## [採用 `Package.swift` 作為依賴項目的 DSL](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，你可以在 `Dependencies.swift` 檔案中定義依賴項目。這種專屬格式導致 [Dependabot](https://github.com/dependabot) 或 [Renovatebot](https://github.com/renovatebot/renovate) 等工具無法自動更新依賴項目。此外，它也為使用者帶來不必要的間接層。因此，我們決定在 Tuist 中只採用 `Package.swift` 來定義依賴項目。如果你曾經使用 `Dependencies.swift` 檔案，你需要將 `Tuist/Dependencies.swift` 的內容移至根目錄下的 `Package.swift`，並使用 `#if TUIST` 指示詞來設定整合。你可以在此閱讀更多關於如何整合 Swift Package 依賴項目的資訊：<.localized_link href="/guides/features/projects/dependencies#swift-packages">這裡</.localized_link>

## 將 `tuist cache warm` 重新命名為 `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

為求簡潔，我們決定將 `tuist cache warm` 指令重新命名為 `tuist cache`。如果你曾經使用 `tuist cache warm` 指令，你需要更新專案以改用 `tuist cache` 指令。


## 將 `tuist cache print-hashes` 重新命名為 `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我們決定將 `tuist cache print-hashes` 指令重新命名為 `tuist cache --print-hashes`，以明確表示它是 `tuist cache` 指令的一個旗標。如果你曾經使用 `tuist cache print-hashes` 指令，你需要更新專案以改用 `tuist cache --print-hashes` 旗標。

## 移除快取設定檔 {#removed-caching-profiles}

在 Tuist 4 之前，你可以在 `Tuist/Config.swift` 中定義包含快取設定的快取設定檔。我們決定移除此功能，因為在生成過程中使用與生成專案時不同的設定檔可能會造成混淆。此外，這也可能導致使用者使用除錯設定檔來建置應用程式的發布版本，從而產生意外結果。取而代之，我們引入了 `--configuration` 選項，讓你在生成專案時指定要使用的設定。如果你曾經使用快取設定檔，你需要更新專案以改用 `--configuration` 選項。

## 移除 `--skip-cache`，改為使用參數 {#removed-skipcache-in-favor-of-arguments}

我們從 `generate` 指令中移除了 `--skip-cache` 旗標，改為透過參數來控制哪些目標應略過二進位快取。如果你曾經使用 `--skip-cache` 旗標，你需要更新專案以改用參數。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

## [移除簽署功能](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

簽署問題已由社群工具如 [Fastlane](https://fastlane.tools/) 以及 Xcode 本身解決，而且它們做得更好。我們認為簽署對 Tuist 而言屬於過度擴展的目標，專注於專案的核心功能更為合適。如果你曾經使用 Tuist 的簽署功能（即在儲存庫中加密憑證與描述檔，並在生成時將它們安裝到正確位置），你可能需要在專案生成前執行的腳本中複製該邏輯。具體而言：
  - 一個腳本，使用儲存在檔案系統或環境變數中的金鑰來解密憑證與描述檔，並將憑證安裝到金鑰圈，將佈建描述檔安裝到目錄 `~/Library/MobileDevice/Provisioning\ Profiles`。
  - 一個腳本，能夠取得現有的描述檔與憑證並對其進行加密。

> [!TIP]
> **簽署需求**
>
> 簽署需要金鑰圈中存在正確的憑證，且目錄 `~/Library/MobileDevice/Provisioning\ Profiles` 中存在佈建描述檔。你可以使用 `security` 命令列工具將憑證安裝到金鑰圈，並使用 `cp` 命令將佈建描述檔複製到正確的目錄。


## 不再透過 `Dependencies.swift` 整合 Carthage {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，你可以在 `Dependencies.swift` 檔案中定義 Carthage 依賴項，然後透過執行 `tuist fetch` 來取得。我們亦認為這對 Tuist 而言屬於過度擴展的目標，特別是考慮到未來 Swift Package Manager 將成為管理依賴項的首選方式。如果你曾經使用 Carthage 依賴項，你需要直接使用 `Carthage` 將預編譯的 frameworks 和 XCFrameworks 拉取到 Carthage 的標準目錄，然後在你的目標中使用 `TargetDependency.xcframework` 和 `TargetDependency.framework` 案例來引用這些二進位檔。

> [!NOTE]
> **仍然支援 Carthage**
>
> 部分用戶誤以為我們放棄了對 Carthage 的支援。事實並非如此。Tuist 與 Carthage 輸出之間的協定是針對系統儲存的 frameworks 和 XCFrameworks。唯一改變的是負責取得依賴項的一方：過去是由 Tuist 透過 Carthage 處理，現在則由 Carthage 負責。


## 移除 `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，你可以使用 `TargetDependency.packagePlugin` 案例來定義套件外掛程式依賴項。鑑於 Swift Package Manager 引入了新的套件類型，我們決定迭代該 API，使其更具彈性並面向未來。如果你曾經使用 `TargetDependency.packagePlugin`，你需要改為使用 `TargetDependency.package`，並將你想要使用的套件類型作為參數傳遞。

## [移除已棄用的 API](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我們移除了在 Tuist 3 中被標記為已棄用的 API。如果你曾經使用任何已棄用的 API，你需要更新專案以使用新的 API。
