---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# 开始{#get-started}

如果您有为苹果平台（如 iOS）开发应用程序的经验，那么为 Tuist 添加代码应该没什么不同。与开发应用程序相比，有两点区别值得一提：

- **与 CLI 的交互是通过终端进行的。** 用户执行
  Tuist，执行所需的任务，然后成功返回或返回状态代码。在执行过程中，可以通过向标准输出和标准错误发送输出信息来通知用户。没有手势或图形交互，只有用户意图。

- **在 iOS 应用程序中，当应用程序接收到系统或用户事件时，没有运行循环让进程继续运行，等待输入** 。CLI
  在进程中运行，并在工作完成后结束。异步工作可使用
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  或 [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)
  等系统 API 完成，但需要确保在执行异步工作时进程仍在运行。否则，进程将终止异步工作。

如果您没有 Swift 的使用经验，我们推荐您阅读 [Apple 官方书籍](https://docs.swift.org/swift-book/)，以熟悉
Swift 语言和基金会 API 中最常用的元素。

## 最低要求{#minimum-requirements}

向 Tuist 捐款的最低要求是

- macOS 14.0+
- Xcode 16.3+

## 在本地设置项目{#set-up-the-project-locally}

要开始项目工作，我们可以按照以下步骤进行：

- 运行以下命令克隆仓库：`git clone git@github.com:tuist/tuist.git`
- [安装](https://mise.jdx.dev/getting-started.html)。Mise 以提供开发环境。
- 运行`mise install` 安装 Tuist 所需的系统依赖项
- 运行`tuist install` 安装 Tuist 所需的外部依赖项
- (可选）运行`tuist auth login` 访问 <LocalizedLink href="/guides/features/cache">Tuist 缓存</LocalizedLink>
- 运行`tuist generate` 使用 Tuist 本身生成 Tuist Xcode 项目

**生成的项目会自动打开** 。如果需要在未生成的情况下再次打开，请运行`打开 Tuist.xcworkspace` （或使用 Finder）。

::: info XED .
<!-- -->
如果尝试使用`xed .` 打开项目，它将打开软件包，而不是 Tuist 生成的项目。我们建议使用 Tuist 生成的项目来为工具提供狗粮。
<!-- -->
:::

## 编辑项目{#edit-the-project}

如果需要编辑项目，例如添加依赖关系或调整目标，可以使用
<LocalizedLink href="/guides/features/projects/editing">`tuist edit` 命令</LocalizedLink>。这个命令很少用到，但知道它的存在还是很有好处的。

## 运行图易斯特{#run-tuist}

### 从 Xcode{#from-xcode}

要在生成的 Xcode 项目中运行`tuist` ，请编辑`tuist` 方案，并设置要传递给命令的参数。例如，要运行`tuist generate`
命令，可以将参数设置为`generate --no-open` ，以防止生成后打开项目。

使用 Tuist 运行生成命令的方案配置示例](/images/contributors/scheme-arguments.png)。

还必须将工作目录设置为正在生成的项目的根目录。您可以使用`--path` 参数（所有命令都接受该参数）或在方案中配置工作目录，如下所示：


如何设置运行 Tuist 的工作目录的示例](/images/contributors/scheme-working-directory.png)。

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
`tuist` CLI 依赖于`ProjectDescription` 框架是否存在于构建的产品目录中。如果`tuist`
因找不到`ProjectDescription` 框架而无法运行，请先构建`Tuist-Workspace` 方案。
<!-- -->
:::

### 从航站楼{#from-the-terminal}

您可以通过`run` 命令，使用 Tuist 本身运行`tuist` ：

```bash
tuist run tuist generate --path /path/to/project --no-open
```

或者，您也可以直接通过 Swift 软件包管理器运行它：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
