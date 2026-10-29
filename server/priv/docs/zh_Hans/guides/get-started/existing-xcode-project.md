---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect an existing Xcode project to Tuist for the Xcode compilation cache, build and test insights, bundle-size tracking, and preview links, without adopting project generation."
}
---
# Xcode 项目 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

当你希望保持 `.xcodeproj` 或 `.xcworkspace` 原封不动，并在不采用项目生成的情况下引入 Tuist 的功能时，请遵循此路径。下面的每个部分首先介绍当前缺失的内容，然后引导你了解填补这一空白的功能。

## 前提条件

- macOS 系统，配备 **Xcode 26 或更高版本**（编译缓存和现代洞察功能依赖于它）。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接项目

在仓库根目录运行 `tuist init`。当 Tuist 检测到你的工作区时，选择 **集成 `<YourApp>`**，然后在浏览器中进行身份验证并选择应拥有该项目的账户。Tuist 会在根目录写入一个 `Tuist.swift`，用于固定项目句柄，以便你的团队成员和 CI 共享相同的连接。提交它。

如果你是通过编码代理或脚本驱动此过程，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下内容均为可选且相互独立。

## Xcode 编译缓存

Xcode 26 附带了基于文件的编译缓存，但其存储位于机器的 `DerivedData` 内部。干净构建会在本地填充它；由于团队成员和 CI 运行器看不到该存储，因此需要从头重新构建。

`tuist setup cache` 将 Xcode 的编译缓存指向共享的 Tuist 缓存网络。任何开发人员机器或 CI 运行中的命中都将使构建相同版本的每台其他机器受益。

```bash
tuist setup cache
```

在 Xcode 中构建。清除 Derived Data，在第二台机器或 CI 运行器上再次构建。第二次构建完成时间大幅缩短，且 Xcode 的构建报告会显示编译缓存命中情况。

## 构建洞察

Xcode 在日志和构建报告中记录每个目标的构建持续时间。这些数据未按运行次数或机器进行聚合。出现在一个 PR 中的构建时间回归通常仅表现为整体 CI 变慢，而没有关于哪个目标导致此问题或何时发生的明显信号。

构建洞察记录每次构建的持续时间和阶段耗时，以便在仪表板上查看趋势。这是方案中的一行后置操作：

1. 在 Xcode 中：**产品 → 方案 → 编辑方案…**
2. 展开 **构建 → 后置操作**，点击 **+**，选择 **新建运行脚本操作**。
3. 在 **提供构建设置自** 下，选择你的应用目标。
4. 粘贴与你安装 Tuist 的方式相匹配的行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的方案脚本不会继承你 shell 的 `PATH`，因此无法自行找到 mise 的 shim。上面的 Mise 行通过其绝对路径调用 mise，并要求它从 `$SRCROOT` 加载配置，以便选择项目中固定的版本。
5. 构建一次。构建将在几秒内出现在仪表板的 **构建** 选项卡上。

## 测试洞察

Xcode 的测试日志逐次列出每次运行的每个测试结果。它不会聚合你实际需要的跨运行信号：测试失败的频率、上周变慢了多少、是否仅在特定模拟器上失败。在十次 CI 运行中从可靠变为不稳定的测试看起来与单次不幸的运行相同。

测试洞察记录每次测试的结果和持续时间，并关联跨运行的结果。慢速测试、失败和不稳定测试会显示在仪表板的 **测试** 选项卡上。

1. **产品 → 方案 → 编辑方案…**
2. **测试 → 后置操作 → +** → **新建运行脚本操作**。
3. **提供构建设置自** 你的应用目标。
4. 粘贴： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 运行一次测试操作。结果将出现在仪表板的 **测试** 选项卡上。

## 包洞察

IPA 的安装和下载大小会随着每个添加的资源文件和链接的符号而变化。Xcode 按需在 **产品 → 显示归档** 中报告大小，而不是作为系列数据。在合并队列中，添加大资源文件的 PR 与其他任何 PR 无法区分。

包洞察记录每次分析构建的安装和下载大小，并且当超过每个分支的阈值时可以使 PR 检查失败。在构建步骤之后立即将此内容添加到你的 CI 中：

```bash
tuist inspect bundle App.ipa
```

在仪表板上打开 **包洞察** 以查看趋势并配置阈值。

## 预览

TestFlight 在每次分享时都会增加构建和审查的往返过程。直接发送签名的 `.ipa` 需要在配置描述文件中包含接收者的 UDID。对于只想尝试当前分支的设计师或 QA 人员来说，这两种方式都不方便。

预览通过一条命令将构建转换为可在模拟器或设备上运行的可分享链接：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

发送链接。接收者使用 `tuist run <url>` 或 Tuist macOS 应用运行它。

## 让团队加入

缓存和洞察会随着连接到项目的人数增加而累积效应。从仪表板的账户设置中邀请你的团队成员加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">单点登录</.localized_link>（Google、Okta、Microsoft），这样入职只需点击一下，而不是每人执行一次 `tuist auth login`。

## 下一步去哪里

如果你超出了此路径的范围，最大的一步是采用 Tuist 生成的项目。这是一个真正的变化（目标在 Swift 清单中描述，而不是在 `.xcodeproj` 中），但它能解锁模块缓存和选择性测试。<.localized_link href="/guides/get-started/generated-xcode-project">生成的 Xcode 项目</.localized_link> 指南中对此进行了端到端的介绍。
