---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 元数据标签{#metadata-tags}

随着项目规模和复杂性的增加，一次性处理整个代码库可能会变得效率低下。Tuist 提供了**元数据标签**
作为一种方法，将目标组织成逻辑组，并在开发过程中专注于项目的特定部分。

## 什么是元数据标签？{#what-are-metadata-tags}

元数据标签是可以附加到项目目标上的字符串标签。作为标记，它们可以让你

- **对相关目标进行分组** - 标记属于同一功能、团队或架构层的目标
- **集中工作区** - 生成仅包含特定标记目标的项目
- **优化工作流程** - 无需加载代码库中不相关的部分即可处理特定功能
- **选择要保留为源的目标** - 选择缓存时要保留为源的目标组

标签是使用`metadata` 属性在目标上定义的，并以字符串数组的形式存储。

## 定义元数据标记{#defining-metadata-tags}

您可以为项目清单中的任何目标添加标记：

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

## 关注标记目标{#focusing-on-tagged-targets}

标记目标后，就可以使用`tuist generate` 命令创建只包含特定目标的重点项目：

### 按标签聚焦

使用`tag:` 前缀，生成一个包含所有匹配特定标记的目标的项目：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名称聚焦

您还可以按名称关注特定目标：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 聚焦如何发挥作用

当你专注于目标时：

1. **包含的目标** - 生成的项目中包含与您的查询相匹配的目标
2. **依赖关系** - 自动包含重点目标的所有依赖关系
3. **测试目标** - 包括重点目标的测试目标
4. **排除** - 将所有其他目标排除在工作区之外

这意味着您可以获得一个更小、更易于管理的工作空间，其中只包含您在制作功能时所需的内容。

## 标签命名规则{#tag-naming-conventions}

虽然可以使用任何字符串作为标签，但遵循统一的命名规范有助于保持标签的条理性：

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

使用`feature:`,`team:`, 或`layer:` 这样的前缀更容易理解每个标签的目的，并避免命名冲突。

## 使用项目描述助手的标记{#using-tags-with-helpers}

您可以利用<LocalizedLink href="/guides/features/projects/code-sharing">项目描述助手</LocalizedLink>来规范在整个项目中应用标记的方式：

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

## 使用元数据标记的好处{#benefits}

### 改善开发体验

通过专注于项目的特定部分，您可以

- **缩小 Xcode 项目大小** - 使用更小的项目工作，打开和浏览速度更快
- **加快构建速度** - 仅构建当前工作所需的内容
- **提高专注度** - 避免无关代码分散注意力
- **优化索引** - Xcode 索引的代码更少，自动完成速度更快

### 更好地组织项目

标签为组织代码库提供了一种灵活的方式：

- **多个维度** - 按功能、团队、层、平台或任何其他维度标记目标
- **不改变结构** - 添加组织结构而不改变目录布局
- **交叉问题** - 一个目标可属于多个逻辑组别

### 与缓存集成

元数据标签可与<LocalizedLink href="/guides/features/cache">Tuist 的缓存功能</LocalizedLink>完美配合：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳做法 {#best-practices}

1. **从简单的** 开始 - 从单一标记维度（如特征）开始，然后根据需要进行扩展
2. **** - 在所有清单中使用相同的命名规范
3. **记录你的标记** - 在项目文档中保存可用标记及其含义的列表
4. **使用帮助程序** - 利用项目描述帮助程序使标签应用标准化
5. **定期审查** - 随着项目的发展，审查并更新您的标记策略

## 相关功能 {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">代码共享</LocalizedLink> - 使用项目描述助手标准化标签的使用
- <LocalizedLink href="/guides/features/cache">缓存</LocalizedLink> - 结合标签与缓存实现最佳构建性能
- <LocalizedLink href="/guides/features/selective-testing">选择性测试</LocalizedLink> - 仅为已更改的目标运行测试