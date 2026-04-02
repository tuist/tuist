---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 快取{#xcode-cache}

Tuist 支援 Xcode 編譯快取功能，讓團隊能透過建置系統的快取能力，共享編譯產出物。

## 設定{#setup}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
- Xcode 26.0 或更新版本
<!-- -->
:::

若您尚未擁有 Tuist 帳戶及專案，可執行以下指令建立：

```bash
tuist init
```

當您擁有一個引用您的`fullHandle` 的`Tuist.swift` 檔案後，即可透過執行以下指令為您的專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，用於在系統啟動時執行本地快取服務，Swift
[建置系統](https://github.com/swiftlang/swift-build) 會利用此服務來共享編譯產出。此指令需在您的本地環境和 CI
環境中各執行一次。

要在 CI 上設定快取，請確認您已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成驗證</LocalizedLink>。

### 設定 Xcode 建置設定{#configure-xcode-build-settings}

請在您的 Xcode 專案中新增以下建置設定：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

請注意，`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 以及`COMPILATION_CACHE_ENABLE_PLUGIN`
必須作為**使用者自訂建置設定** 進行新增，因為這些設定並未直接顯示在 Xcode 的建置設定介面中：

::: info SOCKET PATH
<!-- -->
當您執行 ``tuist setup cache`` 時，將顯示套接字路徑。該路徑基於您專案的完整句柄，其中斜線已被替換為底線。
<!-- -->
:::

您也可以在執行`xcodebuild` 時，透過添加以下參數來指定這些設定，例如：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
若您的專案是由 Tuist 生成的，則無需手動設定這些設定。

在這種情況下，您只需在`Tuist.swift` 檔案中加入`enableCaching: true` 即可：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### 持續整合 #{continuous-integration}

若要在 CI 環境中啟用快取功能，請執行與本地環境相同的指令：`tuist setup cache` 。

關於驗證，您可以使用 <LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
驗證</LocalizedLink>（建議用於受支援的 CI 提供者），或透過`TUIST_TOKEN` 環境變數使用
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶憑證</LocalizedLink>。

使用 OIDC 驗證的 GitHub Actions 工作流程範例：
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

請參閱
<LocalizedLink href="/guides/integrations/continuous-integration">持續整合指南</LocalizedLink>
以查看更多範例，包括基於標記的驗證以及其他 CI 平台，例如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。
