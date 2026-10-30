---
{
  "title": "元数据标签",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何使用目标元数据标签来组织和聚焦项目的特定部分"
}
---
# 元数据标签 {#metadata-tags}

随着项目规模和复杂度的增加，一次性处理整个代码库可能会变得低效。Tuist 提供 **元数据标签**，用于将 target 组织成逻辑组，并在开发过程中专注于项目的特定部分。

## 什么是元数据标签？ {#what-are-metadata-tags}

元数据标签是可以附加到项目中 target 的字符串标签。它们作为标记，使你能够：

- **对相关 target 进行分组** - 为属于同一功能、团队或架构层的 target 添加标签
- **聚焦工作区** - 生成仅包含带有特定标签的 target 的项目
- **优化工作流** - 专注于特定功能，而无需加载代码库中无关的部分
- **选择保留为源码的 target** - 在缓存时选择希望保留为源码的 target 组

标签通过 target 上的 `metadata` 属性定义，并以字符串数组的形式存储。

## 定义元数据标签 {#defining-metadata-tags}

你可以在项目清单中为任何 target 添加标签：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## 聚焦带标签的 target {#focusing-on-tagged-targets}

为 target 添加标签后，你可以使用 `tuist generate` 命令创建一个聚焦的项目，其中仅包含特定的 target：

### 按标签聚焦

使用 `tag:` 前缀生成包含所有匹配特定标签的 target 的项目：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名称聚焦

你也可以按名称聚焦于特定的 target：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 聚焦的工作原理

当你聚焦于某些 target 时：

1. **包含的 target** - 符合查询条件的 target 会被包含在生成的项目中
2. **依赖项** - 聚焦 target 的所有依赖项会自动包含在内
3. **测试 target** - 聚焦 target 对应的测试 target 会被包含
4. **排除** - 其他所有 target 将从工作区中排除

这意味着你将获得一个更小、更易于管理的工作区，其中仅包含开发功能所需的内容。

## 标签命名规范 {#tag-naming-conventions}

虽然你可以使用任意字符串作为标签，但遵循一致的命名规范有助于保持标签的有序性：

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

使用如 `feature:`、`team:` 或 `layer:` 等前缀，可以更轻松地理解每个标签的用途并避免命名冲突。

## 系统标签 {#system-tags}

Tuist 使用 `tuist:` 前缀表示由系统管理的标签。这些标签由 Tuist 自动应用，可在缓存配置文件中用于定位特定类型的生成内容。

### 可用的系统标签

| 标签 | 描述 |
| --- | --- |
| `tuist:synthesized` | 应用于 Tuist 为静态库和静态框架中的资源处理而创建的合成 bundle target。这些 bundle 出于历史原因存在，旨在提供资源访问 API。 |

### 在缓存配置文件中使用系统标签

你可以在缓存配置文件中使用系统标签来包含或排除合成的 target：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

> [!TIP]
> **合成 Bundle 继承父级标签**
>
> 合成 bundle target 除了接收 `tuist:synthesized` 标签外，还会继承其父 target 的所有标签。这意味着如果你为静态库添加 `feature:auth` 标签，其合成的资源 bundle 将同时拥有 `feature:auth` 和 `tuist:synthesized` 标签。


## 在项目描述辅助工具中使用标签 {#using-tags-with-helpers}

你可以利用 <.localized_link href="/guides/features/projects/code-sharing">项目描述辅助工具</.localized_link> 来标准化标签在整个项目中的应用方式：

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

然后在你的清单中使用它：

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## 使用元数据标签的好处 {#benefits}

### 提升开发体验

通过聚焦于项目的特定部分，你可以：

- **减小 Xcode 项目规模** - 使用更小的项目，打开和导航速度更快
- **加快构建速度** - 仅构建当前工作所需的内容
- **提高专注度** - 避免无关代码的干扰
- **优化索引** - Xcode 索引的代码更少，自动补全更快

### 更好的项目组织

标签提供了一种灵活的方式来组织你的代码库：

- **多维度** - 按功能、团队、层级、平台或其他维度为 target 打标签
- **无需结构调整** - 在不更改目录布局的情况下添加组织结构
- **跨切面关注点** - 单个 target 可以属于多个逻辑组

### 与缓存集成

元数据标签可与 <.localized_link href="/guides/features/cache">Tuist 的缓存功能</.localized_link> 无缝协作：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳实践 {#best-practices}

1. **从简开始** - 从单一标签维度（例如功能）开始，并根据需要扩展
2. **保持一致** - 在所有清单中使用相同的命名规范
3. **记录你的标签** - 在项目文档中维护可用标签及其含义的列表
4. **使用辅助工具** - 利用项目描述辅助工具来标准化标签的应用
5. **定期审查** - 随着项目的发展，审查并更新你的标签策略

## 相关功能 {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">代码共享</.localized_link> - 使用项目描述辅助工具来标准化标签的使用
- <.localized_link href="/guides/features/cache">缓存</.localized_link> - 将标签与缓存结合使用，以获得最佳的构建性能
- <.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link> - 仅对已更改的 target 运行测试
