---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode 缓存 {#xcode-cache}

Tuist 支持 Xcode 的编译缓存，允许团队利用构建系统的缓存功能共享编译工件。

## 设置{#setup}

警告要求
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>
- Xcode 26.0 或更高版本
<!-- -->
:::

如果您还没有 Tuist 帐户和项目，可以通过运行来创建：

```bash
tuist init
```

一旦有了引用`fullHandle` 的`Tuist.swift` 文件，就可以通过运行为项目设置缓存：

```bash
tuist setup cache
```

该命令创建一个
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
以在启动时运行本地缓存服务，Swift [build system](https://github.com/swiftlang/swift-build)
会使用该服务共享编译工件。此命令需要在本地和 CI 环境中运行一次。

要在 CI 上设置缓存，请确保您已通过
<LocalizedLink href="/guides/integrations/continuous-integration#authentication"> 验证</LocalizedLink>。

### 配置 Xcode 构建设置{#configure-xcode-build-settings}

将以下构建设置添加到您的 Xcode 项目中：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

请注意，`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 和`COMPILATION_CACHE_ENABLE_PLUGIN`
需要添加为**用户自定义的构建设置** ，因为它们没有直接暴露在 Xcode 的构建设置 UI 中：

::: info SOCKET PATH
<!-- -->
运行`tuist setup cache` 时将显示套接字路径。它基于项目的完整句柄，下划线替换了斜线。
<!-- -->
:::

您也可以在运行`xcodebuild` 时指定这些设置，方法是添加以下标志，如

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
如果项目由 Tuist 生成，则无需手动设置。

在这种情况下，只需在`Tuist.swift` 文件中添加`enableCaching: true` 即可：
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

要在 CI 环境中启用缓存，需要运行与本地环境相同的命令：`tuist setup cache` 。

此外，您还需要确保`TUIST_TOKEN` 环境变量已设置。您可以根据此处的文档
<LocalizedLink href="/guides/server/authentication#as-a-project"></LocalizedLink>
创建一个环境变量。`_ TUIST_TOKEN` 环境变量_必须在构建步骤中存在，但我们建议在整个 CI 工作流程中都设置它。

GitHub 操作的工作流程示例如下：
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
