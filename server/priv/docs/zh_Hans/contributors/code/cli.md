---
{
  "title": "CLI",
  "titleTemplate": ":title · 代码 · 贡献者 · Tuist",
  "description": "为 Tuist CLI 做出贡献。"
}
---
# CLI {#cli}

来源：[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) 和 [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途 {#what-it-is-for}

CLI 是 Tuist 的核心。它负责项目生成、自动化工作流（测试、运行、依赖图和检查），并提供与 Tuist 服务器的接口，以支持身份验证、缓存、洞察、预览、注册表和选择性测试等功能。

## 如何贡献 {#how-to-contribute}

### 要求 {#requirements}

- macOS 14.0+
- Xcode 26+

### 本地设置 {#set-up-locally}

- 克隆仓库：`git clone git@github.com:tuist/tuist.git`
- 使用[官方安装脚本](https://mise.jdx.dev/getting-started.html)安装 Mise（不要使用 Homebrew），然后运行 `mise install`
- 安装 Tuist 依赖：`tuist install`
- 生成工作区：`tuist generate`

生成的项目会自动打开。如果之后需要重新打开，请运行 `open Tuist.xcworkspace`。

> [!NOTE]
> **Xed .**
>
> 如果你尝试使用 `xed .` 打开项目，它将打开包而不是 Tuist 生成的工作区。请使用 `Tuist.xcworkspace`。


### 运行 Tuist {#run-tuist}

#### 从 Xcode {#from-xcode}

编辑 `tuist` scheme 并设置参数，例如 `generate --no-open`。将工作目录设置为项目根目录（或使用 `--path`）。

> [!WARNING]
> **ProjectDescription 编译**
>
> CLI 依赖于 `ProjectDescription` 的构建。如果运行失败，请先构建 `Tuist-Workspace` scheme。


#### 从终端 {#from-the-terminal}

首先生成工作区：

```bash
tuist generate --no-open
```

然后使用 Xcode 构建 `tuist` 可执行文件，并从 DerivedData 运行它：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

或者通过 Swift Package Manager：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
