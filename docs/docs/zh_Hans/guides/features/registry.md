---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# 注册表 {#registry｝

随着依赖关系数量的增加，解决这些问题所需的时间也在增加。CocoaPods](https://cocoapods.org/) 或
[npm](https://www.npmjs.com/) 等其他软件包管理器是集中式的，而 Swift 软件包管理器不是。因此，SwiftPM
需要通过深度克隆每个版本库来解决依赖关系，这可能比集中式方法更耗时、占用更多内存。为了解决这个问题，Tuist
提供了[包注册中心](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)的实现，因此你可以只下载_实际需要的提交_
。注册表中的软件包基于[Swift 软件包索引](https://swiftpackageindex.com/)。-
如果您能在这里找到某个软件包，那么该软件包也能在 Tuist 注册表中找到。此外，这些软件包分布在全球各地，使用边缘存储，以便在解析时将延迟降到最低。

## 用法 {#usage｝

要设置注册表，请在项目目录下运行以下命令：

```bash
tuist registry setup
```

该命令会生成一个注册表配置文件，为你的项目启用注册表。确保该文件已提交，以便你的团队也能受益于注册表。

### 身份验证（可选） {#authentication}

**验证是可选的** 。在未进行身份验证的情况下，使用注册表的速率限制为**，每个 IP 地址每分钟 1,000 次请求** 。要获得**每分钟 20,000
次请求的更高速率限制** ，可以通过运行以下程序进行身份验证：

```bash
tuist registry login
```

信息
<!-- -->
身份验证需要有 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 帐户和项目</LocalizedLink>。
<!-- -->
:::

### 解决依赖关系 {#resolving-dependencies}

要从注册表而不是源代码控制中解决依赖关系问题，请根据项目设置继续阅读：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode 项目</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">使用 Xcode 软件包集成生成项目</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">使用基于 XcodeProj 的软件包集成生成项目</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift 包</LocalizedLink>

要在 CI
上设置注册表，请遵循本指南：<LocalizedLink href="/guides/features/registry/continuous-integration">持续集成</LocalizedLink>。

### 软件包注册表标识符 {#package-registry-identifiers}

在`Package.swift` 或`Project.swift` 文件中使用软件包注册表标识符时，需要将软件包的 URL
转换为注册表约定。注册表标识符的形式总是`{organization}.{repository}`
。例如，要使用`https://github.com/pointfreeco/swift-composable-architecture`
软件包的注册表，软件包注册表标识符应为`pointfreeco.swift-composable-architecture` 。

信息
<!-- -->
标识符不能包含一个以上的点。如果版本库名称中包含点，则用下划线代替。例如，`https://github.com/groue/GRDB.swift`
软件包的注册表标识符为`groue.GRDB_swift` 。
<!-- -->
:::
