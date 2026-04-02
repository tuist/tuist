---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 缓存 {#xcode-cache}

Tuist 支持 Xcode 编译缓存，这使得团队能够利用构建系统的缓存功能共享编译产物。

## 设置{#setup}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
- Xcode 26.0 或更高版本
<!-- -->
:::

如果您还没有 Tuist 账户和项目，可以运行以下命令创建：

```bash
tuist init
```

一旦您拥有了一个引用`fullHandle` 的`Tuist.swift` 文件，即可通过运行以下命令为项目配置缓存：

```bash
tuist setup cache
```

此命令会创建一个
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，用于在启动时运行本地缓存服务，Swift
[构建系统](https://github.com/swiftlang/swift-build) 会利用该服务共享编译产物。此命令需在本地和 CI
环境中各执行一次。

要在 CI 上设置缓存，请确保您已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">登录</LocalizedLink>。

### 配置 Xcode 构建设置{#configure-xcode-build-settings}

请在您的 Xcode 项目中添加以下构建设置：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

请注意，`、COMPILATION_CACHE_REMOTE_SERVICE_PATH、`
以及`、COMPILATION_CACHE_ENABLE_PLUGIN、` 需要作为**用户自定义构建设置** 添加，因为它们在 Xcode
的构建设置界面中并未直接显示：

::: info SOCKET PATH
<!-- -->
运行 ``tuist setup cache`` 时，将显示套接字路径。该路径基于项目的完整句柄，其中斜杠已被下划线替换。
<!-- -->
:::

您还可以在运行`xcodebuild` 时，通过添加以下标志来指定这些设置，例如：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
如果您的项目是由 Tuist 生成的，则无需手动设置这些选项。

在这种情况下，您只需在`Tuist.swift` 文件中添加`enableCaching: true` 即可：
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

### 持续集成 #{continuous-integration}

要在 CI 环境中启用缓存，您需要运行与本地环境相同的命令：`tuist setup cache` 。

对于身份验证，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
身份验证</LocalizedLink>（推荐用于受支持的 CI 提供商），或通过`TUIST_TOKEN` 环境变量使用
<LocalizedLink href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>。

使用 OIDC 身份验证的 GitHub Actions 工作流示例：
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

请参阅
<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>
以获取更多示例，包括基于令牌的身份验证以及 Xcode Cloud、CircleCI、Bitrise 和 Codemagic 等其他 CI 平台。
