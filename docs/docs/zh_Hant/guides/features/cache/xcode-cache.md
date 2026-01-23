---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 快取{#xcode-cache}

Tuist 支援 Xcode 編譯快取功能，團隊可藉此運用建置系統的快取機制共享編譯產物。

## 設定{#setup}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
- Xcode 26.0 或更新版本
<!-- -->
:::

若尚未擁有 Tuist 帳戶與專案，可執行以下指令建立：

```bash
tuist init
```

當您擁有參照`fullHandle` 的`Tuist.swift` 檔案後，即可執行以下指令為專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，用於在啟動時執行本地快取服務，該服務供
Swift [建置系統](https://github.com/swiftlang/swift-build) 用於共享編譯產出物。此指令需在您的本地環境與 CI
環境中各執行一次。

要在 CI 上設定快取，請確保您已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成身份驗證</LocalizedLink>。

### 設定 Xcode 編譯設定{#configure-xcode-build-settings}

請在您的 Xcode 專案中新增以下建置設定：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

請注意，以下項目需新增至**使用者自訂建置設定** ，因其未直接顯示於 Xcode
建置設定介面：`COMPILATION_CACHE_REMOTE_SERVICE_PATH` `
COMPILATION_CACHE_ENABLE_PLUGIN`

::: info SOCKET PATH
<!-- -->
執行`tuist setup cache` 時將顯示套接字路徑。該路徑基於專案完整句柄，其中斜線均替換為底線。
<!-- -->
:::

執行 ``` 時亦可透過添加以下標記指定這些設定，例如：`xcodebuild` `

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
若您的專案由 Tuist 自動生成，則無需手動設定參數。

`` 在這種情況下，您只需在`Tuist.swift 檔案中加入以下內容：`` `並將 `enableCaching: true` 設定為 `true`。
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

要在 CI 環境啟用快取功能，需執行與本地環境相同的指令：`tuist setup cache`

驗證時可選用 <LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
驗證</LocalizedLink>（建議用於支援的 CI 供應商）或透過環境變數`TUIST_TOKEN` 傳遞
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶令牌</LocalizedLink>。

使用 OIDC 驗證的 GitHub Actions 範例工作流程：
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

更多範例請參閱<LocalizedLink href="/guides/integrations/continuous-integration">持續整合指南</LocalizedLink>，內容涵蓋基於憑證的驗證機制，以及其他持續整合平台如
Xcode Cloud、CircleCI、Bitrise 與 Codemagic。
