---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 快取{#xcode-cache}

Tuist 提供對 Xcode 編譯快取的支援，可讓團隊利用建立系統的快取功能來分享編譯工件。

## 設定{#setup}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
- Xcode 26.0 或更新版本
<!-- -->
:::

如果您還沒有 Tuist 帳戶和專案，可以執行下列步驟來建立：

```bash
tuist init
```

一旦您有一個`Tuist.swift` 檔案引用您的`fullHandle` ，您就可以為專案執行快取設定：

```bash
tuist setup cache
```

此指令會建立一個
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
來在啟動時執行本機快取服務，Swift [build system](https://github.com/swiftlang/swift-build)
會使用此服務來分享編譯工件。此指令需要在本機與 CI 環境中執行一次。

若要在 CI 上設定快取，請確定您已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>。

### 設定 Xcode 建立設定{#configure-xcode-build-settings}

將下列建立設定新增至您的 Xcode 專案：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

請注意，`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 和`COMPILATION_CACHE_ENABLE_PLUGIN`
需要新增為**user-defined build settings** ，因為它們並沒有直接暴露在 Xcode 的 build settings UI 中：

::: info SOCKET PATH
<!-- -->
套接字路徑會在執行`tuist setup cache` 時顯示。它以您專案的完整句柄為基礎，並以下劃線取代斜線。
<!-- -->
:::

您也可以在執行`xcodebuild` 時指定這些設定，方法是加入下列旗標，例如：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
如果專案是由 Tuist 產生，則不需要手動設定。

在這種情況下，您只需要在`Tuist.swift` 檔案中加入`enableCaching: true` ：
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

若要在 CI 環境中啟用快取，您需要執行與本機環境相同的指令：`tuist setup cache` 。

此外，您需要確保`TUIST_TOKEN` 環境變數已設定。您可以按照說明文件
<LocalizedLink href="/guides/server/authentication#as-a-project"> 這裡 </LocalizedLink> 建立一個。`TUIST_TOKEN` 環境變數_必須在您的建置步驟中出現_ ，但我們建議您在整個 CI
工作流程中都設定該變數。

GitHub Actions 的示例工作流程如下：
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
