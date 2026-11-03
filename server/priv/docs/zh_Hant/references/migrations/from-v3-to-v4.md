---
{
  "title": "從 v3 到 v4",
  "titleTemplate": ":title · 遷移指南 · 參考資料 · Tuist",
  "description": "本頁面說明如何將 Tuist CLI 從第 3 版遷移至第 4 版。"
}
---
# 從 Tuist v3 升級至 v4 {#from-tuist-v3-to-v4}

隨著 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) 的發布，我們藉此機會為專案引入了一些重大變更，相信這些變更能讓專案在長期使用中更易於維護與操作。本文件說明將專案從 Tuist 3 升級至 Tuist 4 所需進行的變更。

### 不再透過 `tuistenv` 管理版本 {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安裝腳本會安裝一個名為 `tuistenv` 的工具，並在安裝時重新命名為 `tuist`。該工具負責安裝與啟用 Tuist 的不同版本，確保跨環境的一致性。為了縮減 Tuist 的功能範圍，我們決定捨棄 `tuistenv`，改用 [Mise](https://mise.jdx.dev/)；Mise 能完成相同工作，但更具彈性，且可適用於不同工具。若你先前使用 `tuistenv`，必須執行 `curl -Ls https://uninstall.tuist.io | bash` 來解除安裝目前的 Tuist 版本，然後再以你選擇的方式重新安裝。我們強烈建議使用 Mise，因為它能在不同環境中以確定性的方式安裝並啟用版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **Mise 在 CI 環境與 Xcode 專案中的使用**
>
> 若你決定全面採用 Mise 帶來的一致性保證，我們建議查閱如何在 [CI 環境](https://mise.jdx.dev/continuous-integration.html) 與 [Xcode 專案](https://mise.jdx.dev/ide-integration.html#xcode) 中使用 Mise 的文件。


> [!NOTE]
> **支援 Homebrew**
>
> 請注意，你仍可使用 Homebrew 安裝 Tuist；Homebrew 是 macOS 上熱門的套件管理器。你可以在 <.localized_link href="/guides/install-tuist#alternative-homebrew">安裝指南</.localized_link> 中找到使用 Homebrew 安裝 Tuist 的說明。


### 移除 `init` 建構函式，不再用於 `ProjectDescription` 模型 {#dropped-init-constructors-from-projectdescription-models}

為了提升 API 的可讀性與表達力，我們決定從所有 `ProjectDescription` 模型中移除 `init` 建構函式。現在每個模型都提供靜態建構函式，可用來建立模型實體。若你先前使用 `init` 建構函式，必須更新專案以改用靜態建構函式。

> [!TIP]
> **命名慣例**
>
> 我們採用的命名慣例是將模型名稱作為靜態建構函式的名稱。例如，`Target` 模型的靜態建構函式為 `Target.target`。


### 將 `--no-cache` 重新命名為 `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由於 `--no-cache` 旗標語意不明確，我們將其重新命名為 `--no-binary-cache`，以明確表示它指向二進位快取。若你先前使用 `--no-cache` 旗標，必須更新專案以改用 `--no-binary-cache` 旗標。

### 將 `tuist fetch` 重新命名為 `tuist install` {#renamed-tuist-fetch-to-tuist-install}

我們將 `tuist fetch` 指令重新命名為 `tuist install`，以符合業界慣例。若你先前使用 `tuist fetch` 指令，必須更新專案以改用 `tuist install` 指令。

### [採用 `Package.swift` 作為相依性的 DSL](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，你可以在 `Dependencies.swift` 檔案中定義相依性。這種專屬格式導致 [Dependabot](https://github.com/dependabot) 或 [Renovatebot](https://github.com/renovatebot/renovate) 等工具無法自動更新相依性。此外，它也為使用者帶來不必要的間接層。因此，我們決定在 Tuist 中僅採用 `Package.swift` 來定義相依性。若你先前使用 `Dependencies.swift` 檔案，必須將 `Tuist/Dependencies.swift` 的內容移至根目錄下的 `Package.swift`，並使用 `#if TUIST` 指示詞來設定整合。你可以在此閱讀更多關於如何整合 Swift Package 相依性的資訊：<.localized_link href="/guides/features/projects/dependencies#swift-packages">此處</.localized_link>

### 將 `tuist cache warm` 重新命名為 `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

為了簡潔，我們將 `tuist cache warm` 指令重新命名為 `tuist cache`。若你先前使用 `tuist cache warm` 指令，必須更新專案以改用 `tuist cache` 指令。


### 將 `tuist cache print-hashes` 重新命名為 `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我們將 `tuist cache print-hashes` 指令重新命名為 `tuist cache --print-hashes`，以明確表示它是 `tuist cache` 指令的旗標。若你先前使用 `tuist cache print-hashes` 指令，必須更新專案以改用 `tuist cache --print-hashes` 旗標。

### 移除快取設定檔 {#removed-caching-profiles}

在 Tuist 4 之前，你可以在 `Tuist/Config.swift` 中定義包含快取設定的快取設定檔。我們決定移除此功能，因為在生成過程中若使用與生成專案時不同的設定檔，容易造成混淆。此外，這也可能導致使用者使用除錯設定檔來建置應用程式的發行版本，進而產生非預期結果。取而代之的是，我們引入了 `--configuration` 選項，可用於指定生成專案時要使用的設定。若你先前使用快取設定檔，必須更新專案以改用 `--configuration` 選項。

### 移除 `--skip-cache`，改以引數控制 {#removed-skipcache-in-favor-of-arguments}

我們從 `generate` 指令中移除了 `--skip-cache` 旗標，改為透過引數控制哪些目標應略過二進位快取。若你先前使用 `--skip-cache` 旗標，必須更新專案以改用引數。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [移除簽署功能](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

簽署已由 [Fastlane](https://fastlane.tools/) 等社群工具以及 Xcode 本身妥善解決，它們在這方面表現更佳。我們認為簽署對 Tuist 而言屬於延伸目標，最好將重心放在專案的核心功能上。若你先前使用 Tuist 的簽署功能（其做法是在儲存庫中加密憑證與描述檔，並在生成時將它們安裝到正確位置），你可能需要在專案生成前執行的腳本中複製該邏輯。具體來說：
  - 一個腳本，使用儲存在檔案系統或環境變數中的金鑰來解密憑證與描述檔，並將憑證安裝至金鑰圈，將佈建描述檔安裝至目錄 `~/Library/MobileDevice/Provisioning\ Profiles`。
  - 一個腳本，可將現有的描述檔與憑證進行加密。

> [!TIP]
> **簽署需求**
>
> 簽署需要金鑰圈中存在正確的憑證，且目錄 `~/Library/MobileDevice/Provisioning\ Profiles` 中存在佈建描述檔。你可以使用 `security` 命令列工具將憑證安裝至金鑰圈，並使用 `cp` 命令將佈建描述檔複製到正確目錄。


### 不再透過 `Dependencies.swift` 整合 Carthage {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，Carthage 相依性可以在 `Dependencies.swift` 檔案中定義，使用者可透過執行 `tuist fetch` 來取得。我們也認為這對 Tuist 而言屬於延伸目標，特別是考量到未來 Swift Package Manager 將成為管理相依性的首選方式。若你先前使用 Carthage 相依性，必須直接使用 `Carthage` 將預編譯的 Framework 與 XCFramework 拉取至 Carthage 的標準目錄，然後在目標中使用 `TargetDependency.xcframework` 與 `TargetDependency.framework` 案例來參考這些二進位檔。

> [!NOTE]
> **仍支援 Carthage**
>
> 部分使用者誤以為我們移除了對 Carthage 的支援。事實並非如此。Tuist 與 Carthage 輸出之間的協定是針對系統儲存的 Framework 與 XCFramework。唯一改變的是負責取得相依性的對象：過去是由 Tuist 透過 Carthage 處理，現在則由 Carthage 直接處理。


### 移除 `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，你可以使用 `TargetDependency.packagePlugin` 案例來定義套件外掛程式相依性。在看到 Swift Package Manager 引入新的套件類型後，我們決定迭代該 API，使其更具彈性並面向未來。若你先前使用 `TargetDependency.packagePlugin`，必須改為使用 `TargetDependency.package`，並將欲使用的套件類型作為引數傳入。

### [移除已棄用的 API](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我們移除了在 Tuist 3 中標記為已棄用的 API。若你先前使用任何已棄用的 API，必須更新專案以改用新的 API。
