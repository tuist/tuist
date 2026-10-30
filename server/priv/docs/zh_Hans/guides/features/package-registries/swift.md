---
{
  "title": "Swift",
  "titleTemplate": ":title · 包注册表 · 功能 · 指南 · Tuist",
  "description": "借助由 Tuist 全球缓存网络支持的 Tuist Swift 包注册表，将 Swift Package Manager 的依赖解析时间从几分钟缩短到几秒钟。"
}
---
# Swift Package Registry {#swift-package-registry}

随着依赖数量的增加，解析它们所需的时间也会增加。虽然 [CocoaPods](https://cocoapods.org/) 或 [npm](https://www.npmjs.com/) 等其他包管理器是中心化的，但 Swift Package Manager 并非如此。因此，SwiftPM 需要通过深度克隆每个仓库来解析依赖，这不仅耗时，而且比中心化方法占用更多内存。为了解决这个问题，Tuist 提供了 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 的实现，让你只下载你 _真正需要_ 的提交。注册表中的包基于 [Swift Package Index](https://swiftpackageindex.com/)——如果你能在那里找到一个包，那么该包也可以在 Tuist Registry 中找到。此外，这些包通过边缘存储在全球范围内分发，以在解析时实现最低延迟。

## 用法 {#usage}

有两种设置注册表的方法：

### 选项 1：生成期间自动设置（推荐）{#automatic-setup}

如果你使用 Tuist 生成项目，可以通过在 `Tuist.swift` 配置中设置 `registryEnabled` 选项来启用注册表：

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

使用此选项后，`tuist generate` 将自动在工作区中创建注册表配置文件。这样就无需单独运行 `tuist registry setup`。

> [!TIP]
> `registryEnabled` 还会为通过 Xcode 默认 Swift Package Manager 集成（而非 Tuist 基于 XcodeProj 的集成）集成依赖的项目配置注册表。它不会配置 Xcode 从注册表解析使用源代码管理 URL 声明的包。为此，请按照 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析源代码控制包</.localized_link> 中的描述，在每台机器上运行一次 `tuist registry setup`。


### 选项 2：手动设置 {#manual-setup}

要手动设置注册表，请在项目目录中运行以下命令：

```bash
tuist registry setup
```

此命令会生成一个注册表配置文件，为你的项目启用注册表。请确保提交此文件，以便你的团队也能受益于注册表。

### 身份验证（可选）{#authentication}

身份验证是 **可选的**。如果没有身份验证，你可以使用注册表，每个 IP 地址的速率限制为 **每分钟 1,000 次请求**。要获得 **每分钟 20,000 次请求** 的更高速率限制，你可以通过运行以下命令进行身份验证：

```bash
tuist registry login
```

> [!NOTE]
> 身份验证需要 <.localized_link href="/guides/server/accounts-and-projects">Tuist 账户和项目</.localized_link>。


### 解析依赖 {#resolving-dependencies}

要从注册表而不是源代码控制解析依赖，请根据你的项目设置继续阅读：
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

要在 CI 上设置注册表，请遵循此指南：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">持续集成</.localized_link>。

### 包注册表标识符 {#package-registry-identifiers}

当你在 `Package.swift` 或 `Project.swift` 文件中使用包注册表标识符时，需要将包的 URL 转换为注册表约定格式。注册表标识符始终采用 `{organization}.{repository}` 的形式。例如，要为 `https://github.com/pointfreeco/swift-composable-architecture` 包使用注册表，包注册表标识符应为 `pointfreeco.swift-composable-architecture`。

> [!NOTE]
> 标识符不能包含超过一个点。如果仓库名称包含点，则将其替换为下划线。例如，`https://github.com/groue/GRDB.swift` 包的注册表标识符将为 `groue.GRDB_swift`。
