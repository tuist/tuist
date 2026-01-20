---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# 從 Tuist v3 到 v4{#from-tuist-v3-to-v4}

隨著 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0)
的發行，我們藉此機會為專案引入了一些突破性的變更，我們相信長遠來說，這些變更會讓專案更容易使用和維護。本文件概述了從 Tuist 3 升級到 Tuist 4
時，您需要對專案進行的變更。

### 透過`tuistenv 捨棄版本管理` {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安裝腳本會安裝一個工具`tuistenv` ，在安裝時更名為`tuist` 。該工具會負責安裝和啟動 Tuist
版本，以確保跨環境的決定性。為了減少 Tuist 的功能面，我們決定捨棄`tuistenv` ，改用
[Mise](https://mise.jdx.dev/)，這個工具可以執行相同的工作，但更有彈性，可以跨不同的工具使用。如果您之前使用的是`tuistenv`
，您必須執行`curl -Ls https://uninstall.tuist.io | bash` 來解除安裝目前版本的
Tuist，然後再使用您選擇的安裝方式來安裝。我們強烈建議使用 Mise，因為它可以跨環境確定地安裝和啟用版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
如果您決定全面接受 Mise 所帶來的決定性，我們建議您查看有關如何在 [CI
環境](https://mise.jdx.dev/continuous-integration.html)和 [Xcode
專案](https://mise.jdx.dev/ide-integration.html#xcode)中使用 Mise 的說明文件。
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
請注意，您仍可使用 Homebrew 安裝 Tuist，Homebrew 是適用於 macOS 的常用套件管理程式。您可以在
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew"> 安裝指南</LocalizedLink> 中找到如何使用 Homebrew 安裝 Tuist 的說明。
<!-- -->
:::

### Dropped`init` Constructors from`ProjectDescription` models{#dropped-init-constructors-from-projectdescription-models}

為了改善 API 的可讀性與表達能力，我們決定移除所有`ProjectDescription` 模型中的`init`
建構子。現在每個模型都提供一個靜態的建構子，您可以使用它來建立模型的實體。如果您正在使用`init` 建構子，您必須更新您的專案，改用靜態建構子。

::: tip NAMING CONVENTION
<!-- -->
我們遵循的命名慣例是使用模型的名稱作為靜態構建程式的名稱。例如，`Target` 模型的静态构造函数是`Target.target` 。
<!-- -->
:::

### 將`--no-cache` 改名為`--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由於`--no-cache` 這個旗號有歧義，我們決定將它改名為`--no-binary-cache`
，以清楚說明它是指二進位快取。如果您使用`--no-cache` 標誌，您必須更新專案，改用`--no-binary-cache` 標誌。

### 將`tuist fetch` 重新命名為`tuist install` {#renamed-tuist-fetch-to-tuist-install}

我們將`tuist fetch` 指令重新命名為`tuist install` ，以符合業界慣例。如果您使用`tuist fetch`
指令，則必須更新專案，改用`tuist install` 指令。

### [Adopt`Package.swift` as the DSL for dependencies](https://github.com/tuist/tuist/pull/5862){#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，您可以在`Dependencies.swift` 檔案中定義依賴關係。這種專屬格式破壞了
[Dependabot](https://github.com/dependabot) 或
[Renovatebot](https://github.com/renovatebot/renovate)
等工具對自動更新依賴關係的支援。此外，它也為使用者帶來了不必要的間接層級。因此，我們決定採用`Package.swift` 作為在 Tuist
中定義依賴關係的唯一方式。如果您之前使用`Dependencies.swift` 檔案，您必須將`Tuist/Dependencies.swift`
中的內容移至`Package.swift` 的根目錄，並使用`#if TUIST` 指令來設定整合。您可以在此閱讀更多關於如何整合 Swift
套件相依性的資訊<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">。</LocalizedLink>

### 將`tuist cache warm` 重新命名為`tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

為了簡潔起見，我們決定將`tuist cache warm` 指令改名為`tuist cache` 。如果您使用`tuist cache warm`
指令，您必須更新專案，改用`tuist cache` 指令。


### 重新命名`tuist cache print-hashes` 為`tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我們決定將`tuist cache print-hashes` 指令改名為`tuist cache --print-hashes` ，以清楚說明這是`tuist
cache` 指令的旗號。如果您使用`tuist cache print-hashes` 指令，您必須更新專案，改用`tuist cache
--print-hashes` 旗標。

### 移除快取設定檔{#removed-caching-profiles}

在 Tuist 4 之前，您可以在`Tuist/Config.swift`
中定義快取設定檔，其中包含快取的設定。我們決定移除這項功能，因為在產生專案的過程中，如果使用其他設定檔，可能會造成混淆。此外，它可能會導致使用者使用調試設定檔來建立應用程式的釋出版本，這可能會導致意想不到的結果。取而代之，我們引入了`--configuration`
選項，您可以用它來指定生成專案時要使用的配置。如果您使用的是快取設定檔，您必須更新專案，改用`--configuration` 選項。

### 移除`--skip-cache` ，改為使用參數{#removed-skipcache-in-favor-of-arguments}

我們從`產生` 指令中移除`--skip-cache` 這個旗號，改為使用參數來控制哪些目標應該跳過二進位快取。如果您使用`--skip-cache`
標誌，則必須更新專案，改用參數。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [拋棄簽署能力](https://github.com/tuist/tuist/pull/5716)。{#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

簽章問題已經由 [Fastlane](https://fastlane.tools/) 和 Xcode 本身等社群工具解決，它們在這方面做得更好。我們認為簽章是
Tuist 的延伸目標，最好還是專注於專案的核心功能。如果您正在使用 Tuist
的簽章功能，其中包括加密套件庫中的憑證和設定檔，並在產生時將它們安裝在正確的位置，您可能想要在專案產生前執行的自己的腳本中複製這個邏輯。特別是
  - 腳本會使用儲存在檔案系統或環境變數中的金鑰來解密憑證和設定檔，並將憑證安裝在金鑰串中，以及將佈建設定檔安裝在`~/Library/MobileDevice/Provisioning\
    Profiles` 目錄中。
  - 一個可以將現有的設定檔和憑證加密的腳本。

::: tip SIGNING REQUIREMENTS
<!-- -->
簽章需要在 keychain 中有正確的憑證，以及在`~/Library/MobileDevice/Provisioning\ Profiles` 目錄中有
provisioning profile。您可以使用`security` 命令行工具在钥匙串中安装证书，并使用`cp` 命令将供应配置文件复制到正确的目录。
<!-- -->
:::

### 透過`Dependencies.swift 移除 Carthage 整合` {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，Carthage 的相依性可以定義在`Dependencies.swift` 檔案中，使用者可以執行`tuist fetch`
來取得相依性。我們也覺得這是 Tuist 的延伸目標，特別是考慮到未來 Swift 套件管理員將會是管理依賴關係的首選方式。如果您使用 Carthage
的相依性，您必須直接使用`Carthage` ，將預先編譯好的框架和 XCFrameworks 拉到 Carthage
的標準目錄中，然後在您的標籤中使用`TargetDependency.xcframework` 和`TargetDependency.framework`
來引用這些二進位檔。

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
有些使用者理解為我們放棄了 Carthage 支援。我們沒有。Tuist 和 Carthage 輸出的契約是對系統儲存的框架和
XCFrameworks。唯一改變的是誰負責取得相依性。以前是 Tuist 透過 Carthage，現在是 Carthage。
<!-- -->
:::

### 移除`TargetDependency.packagePlugin` API{#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，您可以使用`TargetDependency.packagePlugin` case 定義套件外掛的依賴關係。在看到 Swift
Package Manager 引進新的套件類型之後，我們決定迭代
API，朝向更有彈性、更經得起未來考驗的方向發展。如果您使用`TargetDependency.packagePlugin`
，您必須改用`TargetDependency.package` ，並傳入您要使用的套件類型作為參數。

### [捨棄已廢棄的 API](https://github.com/tuist/tuist/pull/5560){#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我們移除了 Tuist 3 中被標示為已廢棄的 API。 如果您正在使用任何已廢棄的 API，您必須更新專案以使用新的 API。
