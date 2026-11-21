---
{
  "title": "Swift",
  "titleTemplate": ":title · 包注册表 · 功能 · 指南 · Tuist",
  "description": "借助由 Tuist 全球缓存网络支持的 Tuist Swift 包注册表，将 Swift Package Manager 的依赖解析时间从数分钟缩短至数秒。"
}
---
# Swift Package Registry {#swift-package-registry}

随着依赖数量增加，解析依赖所需的时间也会随之增长。与 [CocoaPods](https://cocoapods.org/) 或 [npm](https://www.npmjs.com/) 等集中式包管理器不同，Swift Package Manager 并非集中式架构。因此，SwiftPM 需要通过深度克隆每个仓库来解析依赖，这不仅耗时，而且比集中式方案占用更多内存。为解决这一问题，Tuist 提供了 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 的实现，让你只下载你 _真正需要_ 的提交。Registry 中的包基于 [Swift Package Index](https://swiftpackageindex.com/)——只要能在该索引中找到某个包，它就同样可在 Tuist Registry 中使用。此外，这些包通过边缘存储在全球分发，从而在解析时实现最低延迟。

## 用法 {#usage}

有两种方式可以设置 Registry：

### 选项 1：在生成期间自动设置（推荐） {#automatic-setup}

如果你使用 Tuist 生成项目，可以在 `Tuist.swift` 配置中设置 `registryEnabled` 选项来启用 Registry：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

启用该选项后，`tuist generate` 会自动在工作区中创建 Registry 配置文件。这样就不需要再单独运行 `tuist registry setup`。

> [!TIP]
> `registryEnabled` 还会为通过 Xcode 默认 Swift Package Manager 集成（而非 Tuist 基于 XcodeProj 的集成）来整合依赖的项目配置 Registry。它不会配置 Xcode 从 Registry 解析以源代码管理 URL 声明的包。如需这样做，请在每台机器上运行一次 `tuist registry setup`，具体说明见 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析源代码管理包</.localized_link>。


### 选项 2：手动设置 {#manual-setup}

要手动设置 Registry，请在项目目录中运行以下命令：

```bash
tuist registry setup
```

该命令会生成一个 Registry 配置文件，为你的项目启用 Registry。请确保提交该文件，以便你的团队也能受益于 Registry。

### 身份验证（可选） {#authentication}

身份验证是 **可选的**。不进行身份验证时，你可以使用 Registry，但每个 IP 地址的速率限制为 **每分钟 1,000 次请求**。若要将速率限制提高到 **每分钟 20,000 次请求**，可以通过运行以下命令进行身份验证：

```bash
tuist registry login
```

> [!NOTE]
> 身份验证需要一个 <.localized_link href="/guides/server/accounts-and-projects">Tuist 账户和项目</.localized_link>。


### 解析依赖 {#resolving-dependencies}

要从 Registry 而非源代码管理解析依赖，请根据你的项目设置继续阅读：
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

要在 CI 上设置 Registry，请参考此指南：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">持续集成</.localized_link>。

### 包 Registry 标识符 {#package-registry-identifiers}

当你在 `Package.swift` 或 `Project.swift` 文件中使用包 Registry 标识符时，需要将包的 URL 转换为 Registry 约定格式。Registry 标识符始终采用 `{organization}.{repository}` 的形式。例如，要为 `https://github.com/pointfreeco/swift-composable-architecture` 包使用 Registry，其包 Registry 标识符应为 `pointfreeco.swift-composable-architecture`。

> [!NOTE]
> 标识符不能包含超过一个点。如果仓库名称中包含点，则会替换为下划线。例如，`https://github.com/groue/GRDB.swift` 包的 Registry 标识符为 `groue.GRDB_swift`。
