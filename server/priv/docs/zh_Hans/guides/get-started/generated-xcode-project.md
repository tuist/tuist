---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 入门指南 · 指南 · Tuist",
  "description": "将模块化的 Xcode 项目压缩为声明式 Swift，并解锁模块缓存、选择性测试、包注册表，以及在依赖图之上提供的构建和测试洞察。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

当你希望 Tuist 通过 Swift 清单文件来描述并生成你的 Xcode 项目时，请遵循此路径。生成的项目将模块化 Xcode 项目的复杂性压缩为对依赖图的简洁、声明式描述。它也是模块缓存和选择性测试的严格要求。

下面的每个部分首先介绍当前缺失的功能，然后引导你了解填补这一空白的特性。

## 前提条件

- 安装了 Xcode 的 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 创建项目

查看其运行效果的最快方式是创建一个新项目。在空目录中运行 `tuist init` 并选择 **创建生成的项目**，选择平台，确认名称，然后进行身份验证并选择拥有该项目的账户。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你通过编码代理或脚本驱动此过程，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式形式：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

当 init 完成后，运行 `tuist generate`。Tuist 会在你的清单文件旁边写入一个 `.xcworkspace` 并在 Xcode 中打开它。构建并运行目标。你应该能看到示例应用在模拟器中启动。

这就是“已连接 + 正在生成”的状态。以下内容均为可选且独立。

如果你要迁移现有应用，请先按照 [Xcode 项目迁移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 进行连接，然后返回并继续处理适合你问题的部分。

## 项目生成

`.xcodeproj` 将应用的形状打包到 XML 中：文件引用、构建阶段、目标依赖、方案和构建设置都位于同一棵树中，没有用于将图作为图进行推理的基本原语。随着项目增长，这种形状越来越难以在脑海中把握，而且 Xcode 没有稳定的句柄供工具对其进行哈希处理并在没有任何更改时跳过工作。

生成的项目将依赖图压缩为声明式 Swift。`Project.swift` 直接描述目标、依赖项和资源，Tuist 在其背后维护一个稳定的依赖图模型。该模型解锁了以下部分：模块缓存对其进行哈希处理以重用二进制文件，选择性测试对其进行哈希处理以跳过输入未更改的测试。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

每次 `tuist generate` 都会从清单文件生成一个确定的工作区。将 `.xcodeproj` 和 `.xcworkspace` 添加到 `.gitignore`。

## 模块缓存

从头编译模块化 Xcode 项目会产生每台机器的成本。每位团队成员和每个 CI 运行器都会生成相同对象文件的自己的副本。Xcode 编译缓存缩短了内部循环，但并未消除每个目标的每台机器构建，也无法用预构建的二进制文件替换整个框架。

模块缓存可以做到这一点。它构建图中每个可缓存的依赖项一次（框架、库、捆绑包），根据目标输入的哈希值存储生成的二进制文件，并在后续生成中将目标替换为其二进制文件。未更改的模块不再被编译：

```bash
tuist cache
```

第一次运行会编译所有内容并将二进制文件上传到你的账户。在下一次 `tuist generate` 时，未更改的依赖项会被替换为其缓存的二进制文件，Xcode 会链接 `.xcframework` 而不是从源代码编译。

## 选择性测试

`xcodebuild test` 不知道更改影响了哪些测试，因此 CI 会在每次推送时运行整个套件。随着套件的增长，实际需要运行的内容与实际运行内容之间的差距从几分钟延长到几十分钟。

选择性测试仅运行自上次成功测试运行以来受更改影响的测试，使用项目图和模块缓存所依赖的相同哈希算法：

```bash
tuist test
```

第一次 `tuist test` 会运行所有内容并持久化每个目标的哈希值。后续运行会跳过输入未更改的目标。将 `tuist test` 移入 CI 以替代 `xcodebuild test`，反馈将在几秒内到达，而不是几分钟。

## 包注册表

Swift Package Manager 通过深度克隆每个包的 git 历史记录来解析依赖项，因为包是通过 URL 寻址而不是通过注册表。在具有数十个传递包的项目中，解析在干净检出时需要几分钟，并且在每个 CI 作业中重复。

Tuist 包注册表提供与 Swift Package Index 跟踪的相同的包，但作为真正的注册表，因此 SwiftPM 仅获取你实际需要的提交。通过在 `Tuist.swift` 中设置 `registryEnabled: true` 一次性启用它：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新生成。包解析时间从几分钟降至几秒。

## 构建洞察

Xcode 在日志和构建报告中记录每个目标的构建持续时间。两者均未跨运行或跨机器聚合，因此构建时间回归通常仅表现为整体 CI 变慢。

构建洞察自动记录每次构建的持续时间和生成方案的阶段计时。无需额外配置。在下一次 `tuist generate` + 构建周期后，打开仪表板的 **构建** 选项卡。

## 测试洞察

Xcode 每次运行报告一次每个测试的结果。它不会聚合你实际需要的跨运行信号：不稳定率、周环比持续时间、哪些模拟器变体失败。

测试洞察自动记录每次测试的结果和持续时间以及生成方案，并关联跨运行的结果。不稳定测试、缓慢测试和失败显示在仪表板的 **测试** 选项卡上。当不稳定测试累积时，从仪表板隔离它们，以便它们不再阻止合并。

## 让团队加入

当每个人都使用相同的共享表面时，模块缓存和选择性测试的收益最大。从仪表板的账户设置邀请你的团队成员加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">单点登录</.localized_link>（Google、Okta、Microsoft），以便入职只需点击一下，而不是每人执行一次 `tuist auth login`。
