---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 缓存 {#xcode-cache}

Tuist 支持 Xcode 编译缓存功能，团队可借此利用构建系统的缓存机制共享编译产物。

## 设置{#setup}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
- Xcode 26.0 或更高版本
<!-- -->
:::

若尚未拥有 Tuist 账户及项目，可通过运行以下命令创建：

```bash
tuist init
```

当您拥有`Tuist.swift` 文件并引用`fullHandle` 后，可通过运行以下命令为项目配置缓存：

```bash
tuist setup cache
```

此命令创建一个[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，用于在启动时运行本地缓存服务，该服务由Swift[构建系统](https://github.com/swiftlang/swift-build)用于共享编译产物。此命令需在本地环境和CI环境中各执行一次。

要在 CI 上设置缓存，请确保您已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成身份验证</LocalizedLink>。

### 配置 Xcode 构建设置{#configure-xcode-build-settings}

在您的 Xcode 项目中添加以下构建设置：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

请注意，`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 以及`COMPILATION_CACHE_ENABLE_PLUGIN`
需要作为**用户自定义构建设置** 添加，因为它们未直接暴露在 Xcode 的构建设置界面中：

::: info SOCKET PATH
<!-- -->
运行`tuist setup cache` 时将显示套接字路径。该路径基于项目完整句柄生成，其中斜杠均替换为下划线。
<!-- -->
:::

运行`时，也可通过添加以下标志指定这些设置：xcodebuild`

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
若项目由Tuist生成，则无需手动设置参数。

此时只需在`Tuist.swift` 文件中添加以下内容：`enableCaching: true`
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

要在 CI 环境中启用缓存，需执行与本地环境相同的命令：`tuist setup cache` 。

认证时可选择使用<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC认证</LocalizedLink>（推荐用于支持的CI提供商）或通过`环境变量TUIST_TOKEN`
获取<LocalizedLink href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>。

使用 OIDC 认证的 GitHub Actions 示例工作流：
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

更多示例请参阅<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>，包括基于令牌的认证以及Xcode
Cloud、CircleCI、Bitrise和Codemagic等其他CI平台。
