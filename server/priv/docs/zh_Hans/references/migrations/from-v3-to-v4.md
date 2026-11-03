---
{
  "title": "从 v3 到 v4",
  "titleTemplate": ":title · 迁移 · 参考 · Tuist",
  "description": "本页介绍如何将 Tuist CLI 从版本 3 迁移到版本 4。"
}
---
# 从 Tuist v3 迁移到 v4 {#from-tuist-v3-to-v4}

随着 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) 的发布，我们借此机会对项目引入了一些破坏性变更，相信这些变更能让项目在长期更易于使用和维护。本文档概述了将项目从 Tuist 3 升级到 Tuist 4 所需进行的变更。

### 不再通过 `tuistenv` 管理版本 {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安装脚本会安装一个名为 `tuistenv` 的工具，该工具在安装时会被重命名为 `tuist`。该工具负责安装和激活 Tuist 的不同版本，确保跨环境的一致性。为了减少 Tuist 的功能面，我们决定弃用 `tuistenv`，转而采用 [Mise](https://mise.jdx.dev/)，这是一款功能相同但更灵活、可跨不同工具使用的工具。如果你之前使用的是 `tuistenv`，则需要运行 `curl -Ls https://uninstall.tuist.io | bash` 来卸载当前版本的 Tuist，然后选择你偏好的安装方法进行重新安装。我们强烈推荐使用 Mise，因为它能够以确定的方式在不同环境中安装和激活版本。

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **在 CI 环境和 Xcode 项目中使用 Mise**
>
> 如果你决定全面采用 Mise 带来的一致性保障，我们建议查阅关于如何在 [CI 环境](https://mise.jdx.dev/continuous-integration.html) 和 [Xcode 项目](https://mise.jdx.dev/ide-integration.html#xcode) 中使用 Mise 的文档。


> [!NOTE]
> **支持 Homebrew**
>
> 请注意，你仍然可以使用 macOS 上流行的包管理器 Homebrew 来安装 Tuist。你可以在 <.localized_link href="/guides/install-tuist#alternative-homebrew">安装指南</.localized_link> 中找到使用 Homebrew 安装 Tuist 的说明。


### 移除 `init` 模型中的 `ProjectDescription` 构造函数 {#dropped-init-constructors-from-projectdescription-models}

为了提高 API 的可读性和表达力，我们决定从所有 `ProjectDescription` 模型中移除 `init` 构造函数。现在每个模型都提供了一个静态构造函数，你可以用它来创建模型实例。如果你之前使用的是 `init` 构造函数，则需要更新项目以改用静态构造函数。

> [!TIP]
> **命名约定**
>
> 我们遵循的命名约定是使用模型名称作为静态构造函数的名称。例如，`Target` 模型的静态构造函数是 `Target.target`。


### 将 `--no-cache` 重命名为 `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由于 `--no-cache` 标志含义模糊，我们决定将其重命名为 `--no-binary-cache`，以明确它指的是二进制缓存。如果你之前使用的是 `--no-cache` 标志，则需要更新项目以改用 `--no-binary-cache` 标志。

### 将 `tuist fetch` 重命名为 `tuist install` {#renamed-tuist-fetch-to-tuist-install}

我们将 `tuist fetch` 命令重命名为 `tuist install`，以符合行业惯例。如果你之前使用的是 `tuist fetch` 命令，则需要更新项目以改用 `tuist install` 命令。

### [采用 `Package.swift` 作为依赖项的 DSL](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，你可以在 `Dependencies.swift` 文件中定义依赖项。这种专有格式破坏了 [Dependabot](https://github.com/dependabot) 或 [Renovatebot](https://github.com/renovatebot/renovate) 等工具自动更新依赖项的支持。此外，它还为用户引入了不必要的间接层。因此，我们决定采用 `Package.swift` 作为在 Tuist 中定义依赖项的唯一方式。如果你之前使用的是 `Dependencies.swift` 文件，则需要将 `Tuist/Dependencies.swift` 中的内容移动到根目录下的 `Package.swift` 中，并使用 `#if TUIST` 指令来配置集成。你可以在此处阅读更多关于如何集成 Swift Package 依赖项的信息：<.localized_link href="/guides/features/projects/dependencies#swift-packages">here</.localized_link>

### 将 `tuist cache warm` 重命名为 `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

为了简洁起见，我们决定将 `tuist cache warm` 命令重命名为 `tuist cache`。如果你之前使用的是 `tuist cache warm` 命令，则需要更新项目以改用 `tuist cache` 命令。


### 将 `tuist cache print-hashes` 重命名为 `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我们决定将 `tuist cache print-hashes` 命令重命名为 `tuist cache --print-hashes`，以明确它是 `tuist cache` 命令的一个标志。如果你之前使用的是 `tuist cache print-hashes` 命令，则需要更新项目以改用 `tuist cache --print-hashes` 标志。

### 移除缓存配置文件 {#removed-caching-profiles}

在 Tuist 4 之前，你可以在 `Tuist/Config.swift` 中定义包含缓存配置的缓存配置文件。我们决定移除此功能，因为在生成过程中使用与生成项目时不同的配置文件会导致混淆。此外，这还可能导致用户使用调试配置文件来构建应用的发布版本，从而产生意外结果。取而代之的是，我们引入了 `--configuration` 选项，你可以用它来指定生成项目时要使用的配置。如果你之前使用的是缓存配置文件，则需要更新项目以改用 `--configuration` 选项。

### 移除 `--skip-cache`，改用参数 {#removed-skipcache-in-favor-of-arguments}

我们从 `generate` 命令中移除了 `--skip-cache` 标志，改为通过参数来控制哪些目标应跳过二进制缓存。如果你之前使用的是 `--skip-cache` 标志，则需要更新项目以改用参数。

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [移除签名功能](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

签名问题已由 [Fastlane](https://fastlane.tools/) 和 Xcode 本身等社区工具很好地解决，它们在这方面做得更加出色。我们认为签名对于 Tuist 来说是一个过度延伸的目标，最好专注于项目的核心功能。如果你之前使用的是 Tuist 的签名功能（即在仓库中加密证书和描述文件，并在生成时将其安装到正确位置），你可能需要在项目生成前运行的自有脚本中复现这一逻辑。具体而言：
  - 一个脚本，使用存储在文件系统或环境变量中的密钥解密证书和描述文件，并将证书安装到钥匙串中，将描述文件安装到目录 `~/Library/MobileDevice/Provisioning\ Profiles` 中。
  - 一个脚本，能够获取现有的描述文件和证书并对其进行加密。

> [!TIP]
> **签名要求**
>
> 签名要求钥匙串中存在正确的证书，且目录 `~/Library/MobileDevice/Provisioning\ Profiles` 中存在正确的描述文件。你可以使用 `security` 命令行工具将证书安装到钥匙串中，并使用 `cp` 命令将描述文件复制到正确的目录。


### 移除通过 `Dependencies.swift` 的 Carthage 集成 {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，Carthage 依赖可以在 `Dependencies.swift` 文件中定义，用户可以通过运行 `tuist fetch` 来获取它们。我们也认为这对 Tuist 来说是一个过度延伸的目标，特别是考虑到 Swift Package Manager 将成为管理依赖的首选方式的未来。如果你之前使用的是 Carthage 依赖，则需要直接使用 `Carthage` 将预编译的框架和 XCFrameworks 拉取到 Carthage 的标准目录中，然后使用 `TargetDependency.xcframework` 和 `TargetDependency.framework` 用例从你的目标中引用这些二进制文件。

> [!NOTE]
> **Carthage 仍然受支持**
>
> 有些用户以为我们放弃了对 Carthage 的支持。事实并非如此。Tuist 与 Carthage 输出之间的约定是使用系统存储的框架和 XCFrameworks。唯一改变的是由谁负责获取依赖。以前是通过 Carthage 由 Tuist 负责，现在则由 Carthage 负责。


### 移除 `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，你可以使用 `TargetDependency.packagePlugin` 用例来定义包插件依赖。在看到 Swift Package Manager 引入新的包类型后，我们决定对 API 进行迭代，使其更加灵活且面向未来。如果你之前使用的是 `TargetDependency.packagePlugin`，则需要改用 `TargetDependency.package`，并将要使用的包类型作为参数传入。

### [移除已弃用的 API](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

我们移除了在 Tuist 3 中标记为已弃用的 API。如果你之前使用了任何已弃用的 API，则需要更新项目以使用新的 API。
