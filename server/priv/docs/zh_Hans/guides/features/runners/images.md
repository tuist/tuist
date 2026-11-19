---
{
  "title": "镜像",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 预装内容：包含 Xcode、模拟器和 Metal 工具链的 macOS 镜像，以及包含 Docker 和 Android SDK 的 Ubuntu 镜像。"
}
---
# 镜像 {#images}

每个 Tuist Runners 作业都在从 Runner 镜像启动的全新虚拟机中开始。你的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>选择镜像：平台、macOS 上的 Xcode 版本以及 Linux 上的 Ubuntu 发行版。作业结束时虚拟机会被丢弃，因此作业安装的任何内容在下一个作业中都会消失。

这些镜像遵循 GitHub 托管的 Runner，保留对工作流重要的部分：相同的用户、主目录和工作区路径、`ImageOS`、无密码的 `sudo`，以及大多数 iOS、macOS 和 Linux 工作流期望的工具。它们故意比 GitHub 的更小，因此下面列出了每个平台的差异。

## 选择镜像 {#choosing-an-image}

- **Xcode、Apple SDK 或模拟器：** 使用锁定到项目构建所用 Xcode 版本的 macOS 配置文件。
- **Docker、Android 构建和模拟器，或其他 Linux 工具：** 使用 Ubuntu 24.04 上的 Linux 配置文件。
- **尚不支持 Ubuntu 24.04 的依赖：** 使用 Ubuntu 22.04 上的 Linux 配置文件。

在 macOS 上，你选择的是 Xcode 而不是镜像：每个 Xcode 版本都是独立的镜像，锁定到 `26.4.1` 的配置文件始终在使用 Xcode 26.4.1 构建的镜像上运行。要运行两个 Xcode 版本，请为每个版本创建一个配置文件。

## macOS {#macos}

macOS Runner 是运行 **macOS 26 Tahoe** 的 Apple silicon（arm64）虚拟机。Runner 的名称包含确切的 macOS 版本，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`，并显示在作业的 **设置作业** 步骤中。

### Xcode {#xcode}

每个镜像包含**恰好一个 Xcode**，通过 `xcode-select` 进行选择，因此 `xcodebuild` 和 `xcrun` 无需额外设置步骤即可使用它。这与 GitHub 托管的镜像的主要区别在于，后者提供多个 Xcode 版本以便在作业时切换。可用版本：

{{runner_macos_xcode_versions}}

- **路径。** Xcode 位于 `/Applications/Xcode_<version>.app`。对于带有补丁组件的版本，`/Applications/Xcode_<major>.<minor>.app` 指向同一个捆绑包，因此 `Xcode_26.4.app` 会解析为 `Xcode_26.4.1.app`。硬编码 GitHub 风格路径或使用 `xcode-select -s` 调用它的工作流仍可正常工作。
- **模拟器。** 与该 Xcode 一起提供的 iOS、tvOS、watchOS 和 visionOS 模拟器运行时已下载到镜像中，因此首次 `xcodebuild test` 时无需获取它们。
- **Metal 工具链。** 自 Xcode 26 起，Metal 编译器不再与 Xcode 捆绑，需要单独下载。每个镜像都包含与其 Xcode 匹配的 Metal 工具链，并为作业运行的用户安装，因此 `xcrun metal` 和包含 `.metal` 源代码的项目无需运行 `xcodebuild -downloadComponent MetalToolchain` 即可构建。
- **Beta 版本。** Beta 配置文件（例如 `27.3-beta`）跟踪该发布的最新 Beta 版本。当 Apple 发布新的 Beta 版本时，镜像会重新构建，配置文件会自动切换到新版本，无需你进行任何更改。

### 预装软件 {#macos-software}

- **Apple 工具：** Xcode（每个镜像一个）、模拟器运行时、Metal 工具链、`xcodes`、`xcbeautify`
- **Swift 和 iOS 工具：** SwiftLint、SwiftFormat、SwiftGen、LicensePlist、Mint、Carthage、CocoaPods、fastlane
- **设备：**`libimobiledevice`、`ideviceinstaller`、`ios-deploy`
- **语言和运行时：** 通过 `rbenv` 安装的 Ruby（2.7 和最新的两个 3.x 版本，最新为默认值）及 Bundler，Node.js 24 及 npm、Yarn 和 pnpm
- **包和版本管理器：** Homebrew、mise
- **版本控制：** Git、Git LFS、Git Credential Manager、GitHub CLI（`gh`）
- **实用工具：**`jq`、`yq`、`curl`、`wget`、`zip`/`unzip`、CMake、GCC、AWS CLI
- **CI 代理：** GitHub Actions runner、Buildkite agent、Bitrise agent 及其 CLI、GitLab job executor
- **其他：** Rosetta 2、已启用 `safaridriver`

工具版本来自镜像构建时的 Homebrew，且镜像会定期重建。要查看 Runner 上的确切版本，请在步骤中打印它，例如 `swiftlint version` 或 `xcodebuild -version`。

### 环境 {#macos-environment}

- **用户和路径。** 作业以 `runner` 身份运行，主目录为 `/Users/runner`，工作区为 `/Users/runner/work`，与 GitHub 托管的 Runner 路径相同，因此硬编码这些路径的操作可以正常工作。
- **`sudo`。** 无密码。该虚拟机专属于你的作业。
- **Homebrew。** 前缀（`/opt/homebrew`）由 `runner` 拥有，因此 `brew install <formula>` 无需 `sudo` 即可工作。`HOMEBREW_NO_AUTO_UPDATE` 已设置。
- **Shell。** 步骤在登录 Shell 中运行，因此 Homebrew、`rbenv` 和 Node.js 都在 `PATH` 中。`LANG` 为 `en_US.UTF-8`。
- **`ImageOS`** 为 `macos26`，与 GitHub 托管的 Runner 一样，供根据它选择预构建二进制文件的设置操作使用。
- **证书。** Apple 的 WWDR (G3) 和 Developer ID (G2) 中间证书位于系统信任存储中，用于签名和公证。
- **隐私权限。** 预先授予两项 macOS 隐私批准，与 GitHub 托管的镜像一样：通过 Apple Events 脚本化 Finder（`create-dmg` 和 `osascript` 需要），以及 iOS 模拟器对麦克风的访问权限（在 UI 测试中录制音频的应用需要）。模拟器内部的权限（如 `simctl privacy`）仍由你的作业负责。
- **磁盘。** 每个作业开始时至少有 100 GB 的可用磁盘空间。

### 未包含 {#macos-not-included}

- **Tuist CLI。** 在作业中安装它（例如使用 mise），以便你的项目控制版本。
- **其他 Xcode 版本。** 为每个 Xcode 版本使用一个配置文件，而不是使用 `xcode-select`。
- **Docker。** macOS Runner 没有 Docker 守护进程。请使用 Linux 配置文件；参见 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>。
- **GitHub 在 macOS 上捆绑的工具链**（iOS 构建很少需要，例如 Java、Android SDK、.NET、Rust、Python 版本或浏览器）。请在步骤中使用 Homebrew、mise 或设置操作安装它们。

## Linux {#linux}

Linux Runner 是运行在 **Ubuntu 24.04** 或 **Ubuntu 22.04** 上的 x86_64 (amd64) 虚拟机，具体由配置文件选择。请参阅 <.localized_link href="/guides/features/runners/profiles#linux">配置文件</.localized_link> 了解如何选择发行版。

### 预装软件 {#linux-software}

- **构建工具链：**`build-essential`（GCC、G++、make）、autoconf、automake、libtool、`pkg-config`、CMake、Ninja、m4、bison、flex、gettext
- **开发头文件：** OpenSSL、libffi、zlib、bzip2、readline、SQLite、ncurses、libxml2、libxslt、libyaml、libcurl、uuid
- **Python：** Python 3，附带 `pip` 和 `venv`（Ubuntu 发行版的版本）
- **容器：** Docker CLI（含 Buildx 和 Compose）；守护进程与作业并行运行（参见 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>）
- **Kubernetes：**`kubectl`、Helm
- **Android：** Android SDK 位于 `/usr/local/lib/android/sdk`，包含命令行工具、平台工具，以及从 API 34 开始的所有平台和构建工具版本，已接受许可协议
- **版本控制：** Git、Git LFS、OpenSSH 客户端、GitHub CLI（`gh`）
- **数据库客户端：** PostgreSQL、MariaDB、Redis（`redis-cli`）、SQLite
- **归档：**`tar`、`zip`/`unzip`、`xz`、`bzip2`、`p7zip`、`zstd`
- **实用工具：**`curl`、`wget`、`jq`、ripgrep、`fd`、`tree`、`less`、`vim`、HTTPie、`netcat`、`dig`、`ip`、`ping`、`file`
- **CI 代理：** GitHub Actions runner、Buildkite agent、Bitrise agent 及其 CLI、GitLab job executor

### 环境 {#linux-environment}

- **用户和路径。** 作业以 `runner`（UID 1000）身份运行，主目录为 `/home/runner`，属于 `docker` 组，可使用无密码 `sudo`。
- **`ImageOS`** 为 `ubuntu24` 或 `ubuntu22`，与 GitHub 托管的 Runner 匹配。
- **Android。**`ANDROID_HOME` 和 `ANDROID_SDK_ROOT` 指向 SDK。模拟器未预装；参见 <.localized_link href="/guides/features/runners#android-emulators">Android 模拟器</.localized_link>。
- **区域设置。**`LANG` 和 `LC_ALL` 为 `C.UTF-8`，且 `DEBIAN_FRONTEND` 为 `noninteractive`，因此 `sudo apt-get install` 不会提示。

### 未包含 {#linux-not-included}

Linux 镜像涵盖基本的构建需求，而非 GitHub 预装的每种语言工具链。请使用常规的设置操作（`actions/setup-java`、`actions/setup-node`、`actions/setup-go`、`ruby/setup-ruby`）、mise 或 `apt-get` 安装作业所需的内容：

- **语言运行时**，例如 Java、Node.js、Go、Ruby、.NET 和 Rust。
- **Android NDK。** 使用 `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` 安装你需要的版本。`ANDROID_NDK_HOME` 保持未设置状态，以便在缺少 NDK 时构建明确失败，而不是指向不存在的 NDK。
- **浏览器**以及除 `kubectl`、Helm 和 `gh` 之外的云 CLI。

若要在作业之间保留工具链而非每次重新安装，请将其放在 <.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link> 上。

## 镜像更新 {#image-updates}

当 Apple 发布新的 Xcode 或测试版、CI 代理更新或我们更改镜像本身时，会重建镜像。作业始终在完整且经过测试的镜像上运行：新镜像会逐步部署到集群中，且在作业运行期间绝不会更改。

如果工作流依赖的工具缺失，请 [联系我们](mailto:contact@tuist.dev) 或在 [社区 Slack](https://slack.tuist.dev) 中提问。
