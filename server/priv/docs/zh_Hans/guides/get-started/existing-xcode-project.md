---
{
  "title": "Xcode 项目",
  "titleTemplate": ":title · 入门指南 · 教程 · Tuist",
  "description": "将现有 Xcode 项目连接到 Tuist，以使用 Xcode 编译缓存、构建与测试洞察、包大小跟踪和预览链接，无需采用项目生成。"
}
---
# Xcode 项目 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

如果你希望保持 `.xcodeproj` 或 `.xcworkspace` 原封不动，并在不采用项目生成的情况下引入 Tuist 的功能，请遵循此路径。以下每个部分都会先指出当前的缺失之处，然后引导你使用填补该空白的功能。

## 前置条件

- macOS 系统，需安装 **Xcode 26 或更高版本**（编译缓存和现代洞察功能依赖于此）。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接项目

在仓库根目录运行 `tuist init`。当 Tuist 检测到你的工作区时，选择 **集成 `<YourApp>`**，然后在浏览器中进行身份验证并选择应拥有该项目的账户。Tuist 会在根目录写入一个 `Tuist.swift`，用于固定项目句柄，以便你的团队成员和 CI 共享相同的连接。提交此文件。

如果你通过编码代理或脚本执行此操作，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式形式：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下内容均为可选且相互独立。

## Xcode 编译缓存

Xcode 26 附带了按文件划分的编译缓存，但其存储位于机器的 `DerivedData` 内部。全新构建会在本地填充该缓存；但由于其他机器无法访问该存储，团队成员和 CI 运行器仍需从头开始重新构建。

`tuist setup cache` 将 Xcode 的编译缓存指向共享的 Tuist 缓存网络。任何开发人员机器或 CI 运行中的缓存命中都将惠及构建相同版本的其他所有机器。

```bash
tuist setup cache
```

在 Xcode 中构建。清除 Derived Data，然后在第二台机器或 CI 运行器上再次构建。第二次构建所需时间大幅缩短，且 Xcode 的构建报告会显示编译缓存命中情况。

## 构建洞察

Xcode 会在日志和构建报告中记录每个目标的构建持续时间。这些数据不会跨运行或跨机器进行聚合。出现在某个 PR 中的构建时间回归通常只表现为整体 CI 变慢，而没有关于哪个目标导致该问题或何时发生的明显信号。

构建洞察会记录每次构建的持续时间和阶段耗时，以便在仪表板上查看趋势。这只需在你的 Scheme 中添加一行后处理动作：

1. 在 Xcode 中：**Product → Scheme → Edit Scheme…**
2. 展开 **Build → Post-actions**，点击 **+**，选择 **New Run Script Action**。
3. 在 **Provide build settings from** 下，选择你的应用目标。
4. 粘贴与你的 Tuist 安装方式相匹配的行： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode 的 Scheme 脚本不会继承你 Shell 的 `PATH`，因此无法自行找到 mise 的 shim。上述 Mise 命令通过绝对路径调用 mise，并要求其从 `$SRCROOT` 加载配置，以便选择项目中固定的版本。
5. 构建一次。构建记录将在几秒内出现在仪表板的 **Builds** 选项卡上。

## 测试洞察

Xcode 的测试日志每次运行仅列出单个测试结果。它不会聚合你真正需要的跨运行信号：测试失败的频率、上周变慢了多少、是否仅在特定模拟器上失败。在十次 CI 运行中从可靠逐渐变为不稳定的测试，看起来与单次运气不佳的运行无异。

测试洞察会记录每次测试的结果和持续时间，并关联跨运行的结果。缓慢的测试、失败和不稳定测试会显示在仪表板的 **Tests** 选项卡上。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. **Provide build settings from** 你的应用目标。
4. 粘贴： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 运行一次测试动作。结果将出现在仪表板的 **Tests** 选项卡上。

## 包洞察

IPA 的安装和下载大小会随着每个添加的资源文件和链接的符号而变化。Xcode 仅在 **Product → Show Archive** 中按需报告大小，而非作为系列数据跟踪。添加了大型资源文件的 PR 在合并队列中与其他 PR 并无区别。

包洞察会记录每次分析构建的安装和下载大小，并在超过分支阈值时使 PR 检查失败。在构建步骤之后立即将此内容添加到你的 CI 中：

```bash
tuist inspect bundle App.ipa
```

在仪表板上打开 **Bundle insights** 以查看趋势并配置阈值。

## 预览

TestFlight 在每次分享时都会增加构建和审查的往返流程。直接发送签名的 `.ipa` 需要在配置描述文件中包含接收者的 UDID。对于只想尝试当前分支的设计师或 QA 人员来说，这两种方式都不方便。

预览功能将构建转换为可通过一个命令在模拟器或设备上运行的共享链接：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

发送链接。接收者可以使用 `tuist run <url>` 或 Tuist macOS 应用运行它。

## 邀请团队加入

缓存和洞察的价值会随着连接到项目的人数增加而累积。从仪表板的账户设置中邀请你的团队成员加入组织，并配置<.localized_link href="/guides/integrations/authentication/sso">单点登录</.localized_link>（Google、Okta、Microsoft），让入职流程只需点击一下，而非每人执行一次`tuist auth login`。

## 下一步

如果你超越了这一阶段，最大的步骤是采用 Tuist 生成的项目。这是一个实质性的变化（目标在 Swift 清单文件中描述，而不是在`.xcodeproj`中），但它能解锁模块缓存和选择性测试。<.localized_link href="/guides/get-started/generated-xcode-project">生成的 Xcode 项目</.localized_link>指南涵盖了端到端的完整流程。
