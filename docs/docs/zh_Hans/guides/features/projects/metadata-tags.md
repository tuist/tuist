---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 元数据标签{#metadata-tags}

随着项目规模和复杂度的增长，同时处理整个代码库可能变得低效。Tuist提供**元数据标签** ，可将目标组织成逻辑分组，在开发过程中聚焦项目特定部分。

## 什么是元数据标签？{#what-are-metadata-tags}

元数据标签是可附加于项目目标的字符串标记，其作为标识符可实现以下功能：

- **将相关目标分组** - 为属于同一功能、团队或架构层的目标添加标签
- **聚焦工作区** - 生成仅包含特定标签目标的项目
- **优化工作流程** - 专注开发特定功能，无需加载代码库中无关部分
- **选择要保留为源的目标** - 选择缓存时希望保留为源的目标组

标签通过目标对象的`元数据` 属性定义，并以字符串数组形式存储。

## 元数据标签定义{#defining-metadata-tags}

您可以在项目清单中的任何目标添加标签：

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

## 专注于标记目标{#focusing-on-tagged-targets}

完成目标标记后，可使用`tuist generate` 命令创建仅包含特定目标的聚焦项目：

### 按标签聚焦

使用`标签：` 前缀可生成包含所有匹配特定标签目标的项目：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名称聚焦

您也可通过名称指定特定翻译目标：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 焦点机制原理

当你聚焦目标时：

1. **包含的目标** - 与您的查询匹配的目标已包含在生成的项目中
2. **依赖项** - 所有聚焦目标的依赖项均自动包含
3. **测试目标** - 包含当前聚焦目标的测试目标
4. **排除项** - 工作区中排除所有其他目标

这意味着您将获得更小巧、更易管理的操作空间，其中仅包含您开发功能所需的内容。

## 标签命名规范{#tag-naming-conventions}

虽然可使用任意字符串作为标签，但遵循统一命名规范有助于保持标签条理清晰：

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

使用前缀如：`（功能）:`,`（团队）:`, 或`（层级）:` ，可清晰传达各标签用途并避免命名冲突。

## 系统标签{#system-tags}

Tuist使用`tuist:` 前缀作为系统管理标签。这些标签由Tuist自动添加，可在缓存配置文件中用于定位特定类型的生成内容。

### 可用系统标签

| 标签                  | 描述                                                            |
| ------------------- | ------------------------------------------------------------- |
| `tuist:synthesized` | 适用于 Tuist 为静态库和静态框架资源处理创建的合成资源包目标。这些资源包因历史原因而存在，旨在提供资源访问 API。 |

### 使用带缓存配置文件的系统标签

您可在缓存配置文件中使用系统标签来包含或排除合成的目标：

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

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
合成资源包目标除继承父目标的所有标签外，还会附加`tuist:synthesized` 标签。这意味着若为静态库添加`feature:auth`
标签，其合成资源包将同时包含`feature:auth` 标签与`tuist:synthesized` 标签。
<!-- -->
:::

## 使用项目描述辅助工具中的标签{#using-tags-with-helpers}

可利用
<LocalizedLink href="/guides/features/projects/code-sharing">项目描述辅助工具</LocalizedLink>
统一项目中标签的添加规范：

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

然后在清单文件中使用它：

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

## 使用元数据标签的优势{#benefits}

### 优化开发体验

通过聚焦项目中的特定部分，您可以：

- **缩减Xcode项目体积** - 使用更小巧的项目，实现更快的打开与导航速度
- **加速构建** - 仅构建当前工作所需内容
- **提升专注度** - 避免无关代码造成的干扰
- **优化索引功能** - Xcode索引更少代码，加速自动完成功能

### 更优的项目组织

标签为组织代码库提供了灵活的方式：

- **多维度** - 按功能、团队、层级、平台或其他维度标记目标
- **不改变结构** - 在不改变目录布局的前提下添加组织结构
- **横切关注点** - 单个目标可属于多个逻辑组

### 与缓存的集成

元数据标签与<LocalizedLink href="/guides/features/cache">Tuist的缓存功能</LocalizedLink>无缝兼容：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳做法 {#best-practices}

1. **从简单开始** - 先从单一标注维度（如特征）着手，再根据需要扩展
2. **保持一致性** - 在所有清单文件中使用相同的命名规范
3. **文档化标签** - 在项目文档中维护可用标签及其含义的列表
4. **使用辅助工具** - 利用项目描述辅助工具规范标签应用
5. **定期审查** - 随着项目发展，请定期审查并更新标记策略

## 相关功能{#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">代码共享</LocalizedLink>
  - 使用项目描述辅助工具规范标签使用
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> -
  结合缓存功能优化构建性能
- <LocalizedLink href="/guides/features/selective-testing">选择性测试</LocalizedLink>
  - 仅对变更的目标运行测试
