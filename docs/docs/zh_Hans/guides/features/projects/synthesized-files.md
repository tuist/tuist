---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 合成文件 {#synthesized-files}

Tuist 可以在生成时生成文件和代码，从而为 Xcode 项目的管理和工作带来一些便利。在本页中，您将了解到这一功能，以及如何在您的项目中使用它。

## 目标资源 {#target-resources}

Xcode 项目支持向目标添加资源。然而，它们也给团队带来了一些挑战，尤其是在处理模块化项目时，源代码和资源经常被移动：

- **运行时访问不一致**
  ：资源在最终产品中的最终位置以及访问方式取决于目标产品。例如，如果目标产品是应用程序，资源就会被复制到应用程序捆绑包中。这就导致访问资源的代码要对捆绑结构做出假设，这并不理想，因为这会使代码更难推理，资源也更难移动。
- **不支持资源的产品**
  ：有些产品（如静态库）不是捆绑包，因此不支持资源。因此，您必须使用不同的产品类型，例如框架，这可能会给您的项目或应用程序增加一些开销。例如，静态框架将静态链接到最终产品，而构建阶段只需要将资源复制到最终产品。或者动态框架，Xcode
  会将二进制文件和资源都复制到最终产品中，但会增加应用程序的启动时间，因为框架需要动态加载。
- **容易出现运行时错误**
  ：资源由其名称和扩展名（字符串）标识。因此，在尝试访问资源时，如果其中任何一项出现错字，都会导致运行时错误。这种情况并不理想，因为在编译时无法捕获，可能导致发布时崩溃。

Tuist 通过**综合了访问捆绑包和资源的统一接口** ，抽象出了实现细节，从而解决了上述问题。

建议发出警告
<!-- -->
尽管通过图易士合成接口访问资源不是必须的，但我们还是建议这样做，因为这样可以使代码更容易推理，资源更容易移动。
<!-- -->
:::

## 资源 {#resources｝

Tuist 提供了一些接口，用于在 Swift 中声明`Info.plist` 或 entitlements
等文件的内容。这对于确保跨目标和跨项目的一致性非常有用，还能利用编译器在编译时捕捉问题。您还可以提出自己的抽象概念来为内容建模，并在不同目标和项目间共享。

生成项目时，Tuist 将合成这些文件的内容，并将其写入`Derived` 目录，与包含定义这些文件的项目的目录相对应。

提示 GITIGNORE 衍生目录
<!-- -->
我们建议将`衍生` 目录添加到项目的`.gitignore` 文件中。
<!-- -->
:::

## 软件包访问器 {#bundle-accessors}

Tuist 合成了一个接口，用于访问包含目标资源的捆绑包。

### 斯威夫特 {#swift}

目标将包含`Bundle` 类型的扩展，以公开捆绑包：

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

在 Objective-C 中，您将获得一个接口`{Target}Resources` 来访问 bundle：

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

内部目标的警告限制
<!-- -->
目前，Tuist 不会为仅包含 Objective-C 源代码的内部目标生成资源包访问器。这是 [issue
#6456](https://github.com/tuist/tuist/issues/6456)中跟踪到的已知限制。
<!-- -->
:::

小贴士 通过工具包为图书馆资源提供支持
<!-- -->
如果目标产品（例如库）不支持资源，Tuist 会将资源包含在产品类型为`bundle` 的目标产品中，以确保资源最终出现在最终产品中，并确保接口指向正确的
bundle。
<!-- -->
:::

## 资源访问器 {#resource-accessors}

资源使用字符串通过名称和扩展名进行标识。这并不理想，因为在编译时无法捕获，可能导致发布时崩溃。为了避免这种情况，Tuist 在项目生成过程中集成了
[SwiftGen](https://github.com/SwiftGen/SwiftGen)
来合成访问资源的接口。有了它，您就可以利用编译器捕捉任何问题，放心地访问资源。

Tuist 包含
[模板](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)，默认情况下为以下资源类型合成访问器：

| 资源类型  | 合成文件                     |
| ----- | ------------------------ |
| 图像和颜色 | `Assets+{Target}.swift`  |
| 弦乐    | `Strings+{Target}.swift` |
| 列表    | `{NameOfPlist}.swift`    |
| 字体    | `字体+{目标}.swift`          |
| 文件    | `Files+{Target}.swift`   |

> 注：通过在项目选项中传递`disableSynthesizedResourceAccessors` 选项，可按项目禁用资源访问器的合成。

#### 自定义模板 {#custom-templates}

如果您想提供自己的模板来合成其他资源类型的访问器（[SwiftGen](https://github.com/SwiftGen/SwiftGen)必须支持这些资源类型），可以在`Tuist/ResourceSynthesizers/{name}.stencil`
中创建它们，其中名称是资源的驼峰字母大写版本。

| 资源    | 模板名称                       |
| ----- | -------------------------- |
| 字符串   | `字符串模板`                    |
| 资产    | `Assets.stencil`           |
| 核对表   | `Plists.stencil`           |
| 字体    | `字体模板`                     |
| 核心数据  | `CoreData.stencil`         |
| 接口生成器 | `InterfaceBuilder.stencil` |
| json  | `JSON.stencil`             |
| yaml  | `YAML.stencil`             |
| 文件    | `文件模板`                     |

如果要配置合成访问器的资源类型列表，可以使用`Project.resourceSynthesizers` 属性传递要使用的资源合成器列表：

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

信息参考
<!-- -->
您可以查看 [this
fixture](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)
以了解如何使用自定义模板合成资源访问器的示例。
<!-- -->
:::
