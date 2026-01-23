---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# 從 Tuist v3 到 v4{#from-tuist-v3-to-v4}

隨著[Tuist
4](https://github.com/tuist/tuist/releases/tag/4.0.0)的發布，我們藉此機會對專案進行了若干重大變更，相信這些調整將使專案在長期使用與維護上更為便捷。本文檔概述了您需對專案進行的調整，以實現從Tuist
3升級至Tuist 4的過程。

### 已移除透過`tuistenv 進行的版本管理` {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安裝腳本會安裝工具`tuistenv` ，該工具在安裝時會重命名為`tuist` 。此工具負責安裝並啟用 Tuist
版本，確保跨環境的確定性。為精簡 Tuist 的功能介面，我們決定捨棄`tuistenv` ，轉而採用
[Mise](https://mise.jdx.dev/) 工具——該工具功能相同但更具彈性，可跨不同工具使用。 若您先前使用的是`tuistenv`
，請先執行`curl -Ls https://uninstall.tuist.io | bash` 卸除現有 Tuist
版本，再透過您偏好的安裝方式重新安裝。我們強烈建議採用 Mise，因其能跨環境確定性地安裝與啟用版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
若您決定全面採用 Mise 所傳遞的決定論，建議查閱相關文件以瞭解如何在 [CI
環境](https://mise.jdx.dev/continuous-integration.html) 與 [Xcode
專案](https://mise.jdx.dev/ide-integration.html#xcode) 中使用 Mise。
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
請注意，您仍可透過 Homebrew（macOS 熱門套件管理工具）安裝 Tuist。詳細安裝步驟請參閱
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">安裝指南</LocalizedLink>。
<!-- -->
:::

### 移除`init` 構造函式自`ProjectDescription` 模型{#dropped-init-constructors-from-projectdescription-models}

` 為提升 API 的可讀性與表達力，我們決定從所有`ProjectDescription` 模型中移除`init`
構造函式。現所有模型皆提供靜態構造函式供您建立模型實例。若您先前使用`init 構造函式，請更新專案改用靜態構造函式。

::: tip NAMING CONVENTION
<!-- -->
我們遵循的命名規範是將模型名稱作為靜態建構函式的名稱。例如，`Target` 模型的靜態建構函式為`Target.target` 。
<!-- -->
:::

### 將`--no-cache` 更名為`--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由於 ``--no-cache`` 參數含義模糊，我們決定將其更名為 ``--no-binary-cache`` 以明確指向二進位快取。若您先前使用
``--no-cache`` 參數，請更新專案改用 ``--no-binary-cache`` 參數。

### 將`tuist fetch` 重新命名為`tuist install` {#renamed-tuist-fetch-to-tuist-install}

我們將 ``` tuist fetch `` ` 指令更名為 ``` tuist install `` `，以符合產業慣例。若您先前使用的是 ``` tuist
fetch `` ` 指令，請更新專案改用 ``` tuist install `` ` 指令。

### [採用`Package.swift` 作為依賴項的 DSL](https://github.com/tuist/tuist/pull/5862){#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，您可於`Dependencies.swift` 檔案中定義依賴項。此專屬格式導致
[Dependabot](https://github.com/dependabot) 或
[Renovatebot](https://github.com/renovatebot/renovate)
等工具無法自動更新依賴項，更為使用者增添不必要的間接操作。 因此，我們決定採用`Package.swift` 作為 Tuist
中定義依賴項的唯一方式。若您先前使用`Dependencies.swift` 檔案，需將內容從`Tuist/Dependencies.swift`
移至根目錄的`Package.swift` ，並使用`#if TUIST` 指令配置整合。更多 Swift Package 依賴項整合方式
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">請參閱此處說明。</LocalizedLink>

### 將`tuist cache warm` 重新命名為`tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

為簡化操作，我們將指令「`tuist cache warm` 」更名為「`tuist cache` 」。若您先前使用的是「`tuist cache warm`
」指令，請更新專案改用「`tuist cache` 」指令。


### 將`tuist cache print-hashes` 重新命名為`tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我們決定將指令 ``` tuist cache print-hashes` 更名為 ``` tuist cache --print-hashes`
，以明確標示其為指令 ``` tuist cache` 的參數。若您先前使用的是指令 ``` tuist cache print-hashes`
，則需更新專案以改用參數 ``` tuist cache --print-hashes` 。

### 移除快取設定檔{#removed-caching-profiles}

在 Tuist 4 之前，您可在`Tuist/Config.swift`
定義快取設定檔，其中包含快取相關配置。我們決定移除此功能，因其在生成過程中若使用與專案生成時不同的設定檔，可能導致混淆。
此外，此做法可能導致使用者誤用除錯設定檔來建置應用程式的正式版本，進而引發預期外的結果。為此，我們新增了 ``--configuration` 選項（參見`
），您可藉此指定專案生成時所需的配置。若先前使用過快取設定檔，請更新專案改用 ``--configuration` 選項（參見` ）。

### 移除`--skip-cache` 以優先處理參數{#removed-skipcache-in-favor-of-arguments}

` 我們已從 ``` 指令中移除 ``--skip-cache` 參數（參見
`` `），改為透過參數控制二進位快取應跳過的目標。若您先前使用 ``--skip-cache` 參數（參見 `` `），請更新專案改用參數控制。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [已停用簽署功能](https://github.com/tuist/tuist/pull/5716){#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

簽署功能已透過社群工具如[Fastlane](https://fastlane.tools/)及Xcode本身解決，其處理效果更為優異。 我們認為簽署功能對
Tuist 而言屬於延伸目標，更應聚焦於專案的核心功能。若您曾使用 Tuist
的簽署功能（包含加密儲存庫中的憑證與配置檔，並在生成時安裝至正確位置），建議您在專案生成前的自訂腳本中複製此邏輯。具體而言：
  - 此腳本使用儲存於檔案系統或環境變數中的金鑰解密憑證與配置檔，將憑證安裝至金鑰串，並將配置檔安裝至目錄：`~/Library/MobileDevice/Provisioning\
    Profiles`
  - 一個能接收現有配置檔與憑證並進行加密的腳本。

::: tip SIGNING REQUIREMENTS
<!-- -->
簽署作業需滿足以下條件：- 鑰匙串中須存在正確憑證- 配置檔須存放於目錄`~/Library/MobileDevice/Provisioning\
Profiles` 可透過以下命令列工具執行：- 使用`security` 安裝憑證至鑰匙串- 執行`cp` 將配置檔複製至指定目錄
<!-- -->
:::

### 已移除透過 ``` 的 Carthage 整合功能Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，Carthage 依賴項可定義於`Dependencies.swift` 檔案中，使用者執行`tuist fetch`
即可取得。我們認為這對 Tuist 而言是項延伸目標，尤其考量到未來 Swift Package Manager 將成為管理依賴項的首選方式。 若您使用的是
Carthage 依賴項，則需直接透過`Carthage` 將預編譯框架與 XCFrameworks 拉取至 Carthage
標準目錄，再透過以下案例從目標中引用這些二進位檔：`TargetDependency.xcframework`
以及`TargetDependency.framework`

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
部分用戶誤解我們已停止支援 Carthage。事實並非如此。Tuist 與 Carthage 的輸出協議仍指向系統儲存的框架及
XCFrameworks。唯一變動在於依賴項的擷取責任歸屬：過去由 Tuist 透過 Carthage 執行，現改由 Carthage 直接負責。
<!-- -->
:::

### 移除`TargetDependency.packagePlugin` API{#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，您可透過 ``` 設定套件插件依賴關係。` 案例。鑑於 Swift Package Manager 引入新型套件類型，我們決定改進
API 以實現更靈活且具前瞻性的設計。若您曾使用 ``` 設定套件插件依賴關係，` 現需改用 ``` 設定套件依賴關係，` 並將所需套件類型作為參數傳入。

### [已移除過時 API](https://github.com/tuist/tuist/pull/5560){#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我們已移除 Tuist 3 中標記為已棄用的 API。若您曾使用任何已棄用的 API，請務必更新專案以採用新版 API。
