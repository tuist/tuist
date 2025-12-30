---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# 从 Tuist v3 到 v4 {#from-tuist-v3-to-v4}

随着 [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0)
的发布，我们借此机会对项目进行了一些突破性的改动，我们相信从长远来看，这些改动将使项目更易于使用和维护。本文档概述了从 Tuist 3 升级到 Tuist 4
时需要对项目做出的更改。

### 通过`tuistenv 放弃版本管理` {#dropped-version-management-through-tuistenv}

在 Tuist 4 之前，安装脚本会安装一个工具`tuistenv` ，在安装时会更名为`tuist` 。该工具将负责安装和激活 Tuist
版本，以确保跨环境的确定性。为了减少 Tuist 的功能面，我们决定放弃`tuistenv` ，转而使用
[Mise](https://mise.jdx.dev/)，该工具可完成相同的工作，但更加灵活，可用于不同的工具。如果您使用的是`tuistenv`
，则必须卸载当前版本的 Tuist，方法是运行`curl -Ls https://uninstall.tuist.io | bash`
，然后使用您选择的安装方法安装。我们强烈推荐使用 Mise，因为它能在不同环境中确定性地安装和激活版本。

代码组

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

CI 环境和 XCODE 项目中的 MISE 警告
<!-- -->
如果您决定全面接受 Mise 带来的确定性，我们建议您查看有关如何在 [CI
环境](https://mise.jdx.dev/continuous-integration.html)和 [Xcode
项目](https://mise.jdx.dev/ide-integration.html#xcode)中使用 Mise 的文档。
<!-- -->
:::

支持主页信息
<!-- -->
请注意，您仍然可以使用Homebrew来安装Tuist，这是一款适用于macOS的流行软件包管理器。您可以在<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">安装指南</LocalizedLink>中找到如何使用
Homebrew 安装 Tuist 的说明。
<!-- -->
:::

### 从`ProjectDescription` 模型丢弃`init` 构造函数 {#dropped-init-constructors-from-projectdescription-models}

为了提高 API 的可读性和表现力，我们决定从`ProjectDescription` 模型中移除`init`
构造函数。现在，每个模型都提供了一个静态构造函数，您可以用它来创建模型的实例。如果您正在使用`init` 构造函数，则必须更新您的项目以使用静态构造函数。

提示命名大会
<!-- -->
我们遵循的命名惯例是使用模型的名称作为静态构造函数的名称。例如，`Target` 模型的静态构造函数是`Target.target` 。
<!-- -->
:::

### 将`--no-cache` 更名为`--no-binary-cache` {#renamed-nocache-to-nobinarycache}

由于`--no-cache` 标志含糊不清，我们决定将其更名为`--no-binary-cache`
，以明确它指的是二进制缓存。如果使用`--no-cache` 标志，则必须更新项目，改用`--no-binary-cache` 标志。

### 将`tuist fetch` 更名为`tuist install` {#renamed-tuist-fetch-to-tuist-install}

我们将`tuist fetch` 命令更名为`tuist install` ，以便与行业惯例保持一致。如果使用`tuist fetch`
命令，则必须更新项目，改用`tuist install` 命令。

### [采用`Package.swift` 作为依赖项的 DSL](https://github.com/tuist/tuist/pull/5862){#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

在 Tuist 4 之前，您可以在`Dependencies.swift` 文件中定义依赖关系。这种专有格式破坏了
[Dependabot](https://github.com/dependabot) 或
[Renovatebot](https://github.com/renovatebot/renovate)
等工具对自动更新依赖关系的支持。此外，它还为用户带来了不必要的间接性。因此，我们决定将`Package.swift` 作为在 Tuist
中定义依赖关系的唯一方式。如果您使用`Dependencies.swift` 文件，则必须将`Tuist/Dependencies.swift`
中的内容移至`Package.swift` 的根目录，并使用`#if TUIST` 指令配置集成。有关如何集成 Swift
软件包依赖项的更多信息，请参阅此处<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">。</LocalizedLink>

### 将`tuist cache warm` 更名为`tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

为简洁起见，我们决定将`tuist cache warm` 命令更名为`tuist cache` 。如果使用`tuist cache warm`
命令，则必须更新项目，改用`tuist cache` 命令。


### 将`tuist cache print-hashes` 重命名为`tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

我们决定将`tuist cache print-hashes` 命令更名为`tuist cache --print-hashes` ，以明确它是`tuist
cache` 命令的一个标志。如果您使用的是`tuist cache print-hashes` 命令，则必须更新您的项目，改用`tuist cache
--print-hashes` 标志。

### 移除缓存配置文件 {#removed-caching-profiles}

在 Tuist 4 之前，您可以在`Tuist/Config.swift`
中定义缓存配置文件，其中包含缓存的配置。我们决定移除这一功能，因为在生成过程中，如果使用的配置文件与生成项目时使用的配置文件不同，可能会导致混淆。此外，它还可能导致用户使用调试配置文件来构建应用程序的发布版本，从而导致意想不到的结果。为此，我们引入了`--configuration`
选项，用于指定生成项目时要使用的配置。如果使用缓存配置文件，则必须更新项目，使用`--configuration` 选项。

### 已移除`--skip-cache` ，改为使用参数 {#removed-skipcache-in-favor-of-arguments}

我们从`生成` 命令中移除了`--skip-cache` 标志，转而使用参数来控制哪些目标应跳过二进制缓存。如果使用`--skip-cache`
标志，则必须更新项目以使用参数。

代码组

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [已删除的签名功能](https://github.com/tuist/tuist/pull/5716)。{#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

社区工具（如 [Fastlane](https://fastlane.tools/) 和 Xcode
本身）已经解决了签名问题，它们在这方面做得更好。我们认为签名只是 Tuist 的一个延伸目标，最好将重点放在项目的核心功能上。如果您正在使用 Tuist
签名功能，其中包括对版本库中的证书和配置文件进行加密，并在生成时将其安装到正确的位置，那么您可能希望在项目生成前运行的脚本中复制这一逻辑。特别是
  - 脚本会使用存储在文件系统或环境变量中的密钥解密证书和配置文件，并将证书安装到钥匙串中，将配置文件安装到`~/Library/MobileDevice/Provisioning\
    Profiles` 目录中。
  - 该脚本可对现有配置文件和证书进行加密。

提示签名要求
<!-- -->
签名需要在钥匙串中安装正确的证书，并在`~/Library/MobileDevice/Provisioning\ Profiles`
目录中安装预配置文件。您可以使用`security` 命令行工具在钥匙串中安装证书，并使用`cp` 命令将供应配置文件复制到正确的目录。
<!-- -->
:::

### 通过`Dependencies.swift 删除迦太基集成` {#dropped-carthage-integration-via-dependenciesswift}

在 Tuist 4 之前，迦太基的依赖关系可以定义在`Dependencies.swift` 文件中，然后用户可以通过运行`tuist fetch`
来获取。我们还认为这是 Tuist 的一个扩展目标，特别是考虑到未来 Swift 包管理器将成为管理依赖关系的首选方式。如果您使用 Carthage
依赖项，则必须直接使用`Carthage` 将预编译框架和 XCFrameworks 拉入 Carthage
的标准目录，然后使用`TargetDependency.xcframework` 和`TargetDependency.framework`
从您的标签中引用这些二进制文件。

信息 CARTHAGE 仍然得到支持
<!-- -->
有些用户认为我们放弃了对 Carthage 的支持。我们没有。Tuist 与 Carthage 输出之间的契约是系统存储框架和
XCFrameworks。唯一改变的是谁负责获取依赖关系。以前是 Tuist 通过 Carthage，现在是 Carthage。
<!-- -->
:::

### 已删除`TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

在 Tuist 4 之前，您可以使用`TargetDependency.packagePlugin` 案例来定义包插件依赖关系。在看到 Swift
包管理器引入了新的包类型后，我们决定对 API 进行迭代，使其更灵活、更面向未来。如果您正在使用`TargetDependency.packagePlugin`
，则必须使用`TargetDependency.package` ，并将您要使用的包类型作为参数传递。

### [已删除的废弃 API](https://github.com/tuist/tuist/pull/5560){#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}（已停用的 API

我们删除了 Tuist 3 中被标记为过时的 API。 如果您正在使用任何过时的 API，则必须更新您的项目以使用新的 API。
