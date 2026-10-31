---
{
  "title": "合成文件",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 项目中的合成文件。"
}
---
# 生成的文件 {#synthesized-files}

Tuist 可以在生成时创建文件和代码，从而简化 Xcode 项目的管理和开发工作。在本页中，你将了解这项功能以及如何在项目中使用它。

## 目标资源 {#target-resources}

Xcode 项目支持向目标添加资源。然而，这会给团队带来一些挑战，尤其是在处理模块化项目时，因为源代码和资源经常会被移动：

- **运行时访问不一致**：资源在最终产品中的位置以及访问方式取决于目标的产品类型。例如，如果目标代表一个应用程序，资源会被复制到应用程序包中。这会导致访问资源的代码对包结构做出假设，这并不是理想的做法，因为它使代码更难理解，也不利于资源的迁移。
- **不支持资源的产品类型**：某些产品类型（如静态库）不是包，因此不支持资源。为此，你不得不改用其他产品类型，例如框架，但这可能会给项目或应用增加额外开销。例如，静态框架会静态链接到最终产品，并且需要一个构建阶段来仅将资源复制到最终产品中。或者使用动态框架，Xcode 会将二进制文件和资源都复制到最终产品中，但由于需要动态加载框架，这会增加应用的启动时间。
- **容易出现运行时错误**：资源通过名称和扩展名（字符串）进行标识。因此，任何拼写错误都会导致在尝试访问资源时出现运行时错误。这并不是理想的情况，因为这些错误无法在编译时被捕获，可能会导致发布版本崩溃。

Tuist 通过**生成统一的接口来访问包和资源**来解决上述问题，从而抽象掉实现细节。

> [!WARNING]
> **推荐**
>
> 虽然通过 Tuist 生成的接口访问资源并非强制要求，但我们推荐使用，因为它使代码更易于理解，也更方便资源的迁移。


## 资源 {#resources}

Tuist 提供了在 Swift 中声明文件内容（如 `Info.plist` 或权限配置）的接口。这有助于确保目标和项目之间的一致性，并利用编译器在编译时捕获问题。你还可以创建自己的抽象来建模内容，并在目标和项目之间共享。

当你的项目生成时，Tuist 会合成这些文件的内容，并将它们写入相对于定义它们的项目目录的 `Derived` 目录中。

> [!TIP]
> **将 Derived 目录加入 Gitignore**
>
> 我们建议将 `Derived` 目录添加到项目的 `.gitignore` 文件中。


## 包访问器 {#bundle-accessors}

Tuist 会生成一个接口，用于访问包含目标资源的包。

### Swift {#swift}

目标将包含一个 `Bundle` 类型的扩展，用于暴露该包：

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

在 Objective-C 中，你将获得一个接口 `{Target}Resources` 来访问包：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **内部目标的限制**
>
> 目前，Tuist 不会为仅包含 Objective-C 源代码的内部目标生成资源包访问器。这是一个已知限制，已在 [issue #6456](https://github.com/tuist/tuist/issues/6456) 中跟踪。


> [!TIP]
> **通过包支持库中的资源**
>
> 如果目标产品（例如库）不支持资源，Tuist 会将资源包含在产品类型为 `bundle` 的目标中，以确保其被纳入最终产品，并且接口指向正确的包。这些生成的包会自动标记为 `tuist:synthesized`，并继承其父目标的所有标签，使你能够在 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">缓存配置</.localized_link>中针对它们。


## 资源访问器 {#resource-accessors}

资源通过字符串形式的名称和扩展名进行标识。这并不是理想的做法，因为这些错误无法在编译时被捕获，可能会导致发布版本崩溃。为了防止这种情况，Tuist 在项目生成过程中集成了 [SwiftGen](https://github.com/SwiftGen/SwiftGen)，以生成访问资源的接口。借此，你可以放心地访问资源，并利用编译器捕获任何问题。

Tuist 默认包含用于为以下资源类型生成访问器的 [模板](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)：

| 资源类型 | 生成的文件 |
| --- | ---- |
| 图片和颜色 | `Assets+{Target}.swift` |
| 字符串 | `Strings+{Target}.swift` |
| Plist 文件 | `{NameOfPlist}.swift` |
| 字体 | `Fonts+{Target}.swift` |
| 文件 | `Files+{Target}.swift` |

> 注意：你可以通过向项目选项传递 `disableSynthesizedResourceAccessors` 选项，按项目禁用资源访问器的生成。

#### 自定义模板 {#custom-templates}

如果你想提供自己的模板来为其他资源类型生成访问器（必须由 [SwiftGen](https://github.com/SwiftGen/SwiftGen) 支持），你可以在 `Tuist/ResourceSynthesizers/{name}.stencil` 处创建它们，其中名称是资源名称的驼峰式版本。

| 资源 | 模板名称 |
| --- | --- |
| strings | `Strings.stencil` |
| assets | `Assets.stencil` |
| plists | `Plists.stencil` |
| fonts | `Fonts.stencil` |
| coreData | `CoreData.stencil` |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json | `JSON.stencil` |
| yaml | `YAML.stencil` |
| files | `Files.stencil` |

如果你想配置要为其生成访问器的资源类型列表，可以使用 `Project.resourceSynthesizers` 属性并传入你要使用的资源合成器列表：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **参考**
>
> 你可以查看 [此示例](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)，了解如何使用自定义模板为资源生成访问器。
