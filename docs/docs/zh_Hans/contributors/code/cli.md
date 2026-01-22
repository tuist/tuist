---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI{#cli}

来源：[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
和
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途说明{#what-it-is-for}

命令行界面（CLI）是Tuist的核心。它负责项目生成、自动化工作流（测试、运行、图表和检查），并为认证、缓存、洞察、预览、注册表和选择性测试等功能提供与Tuist服务器的接口。

## 如何贡献{#how-to-contribute}

### 要求{#requirements}

- macOS 14.0+
- Xcode 26+

### 本地设置{#set-up-locally}

- 克隆仓库：`git clone git@github.com:tuist/tuist.git`
- 使用[官方安装脚本](https://mise.jdx.dev/getting-started.html)（非Homebrew）安装Mise，并运行：`mise
  install`
- 安装 Tuist 依赖项：`tuist install`
- 生成工作区：`tuist generate`

生成的项目将自动打开。若需后续重新打开，请运行：`open Tuist.xcworkspace` 。

::: info XED .
<!-- -->
若尝试通过`xed .` 打开项目，将打开包文件而非Tuist生成的工程。请使用`Tuist.xcworkspace` 。
<!-- -->
:::

### 运行 Tuist{#run-tuist}

#### 来自 Xcode{#from-xcode}

编辑`tuist` 方案，设置参数如`generate --no-open` 。将工作目录设为项目根目录（或使用`--path` ）。

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
CLI依赖于`的ProjectDescription（` ）构建完成。若运行失败，请先构建`的Tuist-Workspace（` ）方案。
<!-- -->
:::

#### 来自终端{#from-the-terminal}

首先生成工作区：

```bash
tuist generate --no-open
```

然后使用Xcode构建`tuist` 可执行文件，并从DerivedData中运行它：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

或通过Swift Package Manager：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
