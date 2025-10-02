---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持续集成（CI） {#continuous-integration-ci}

您可以在[持续集成](https://en.wikipedia.org/wiki/Continuous_integration)环境中使用
Tuist。下文将举例说明如何在不同的 CI 平台上实现这一功能。

## 示例 {#examples}

要在 CI 工作流中运行 Tuist 命令，您需要在 CI 环境中安装它。

### Xcode 云 {#xcode-cloud}

在使用 Xcode 项目作为真实源的 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)
中，您需要添加一个
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
脚本来安装 Tuist 并运行所需的命令，例如`tuist generate` ：

代码组

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
:::
### 代码魔力 {#codemagic}

在 [Codemagic](https://codemagic.io) 中，您可以在工作流程中添加一个额外步骤来安装 Tuist：

代码组
```yaml [Mise]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist build
```
```yaml [Homebrew]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist build
```
:::

### GitHub 操作 {#github-actions}

在 [GitHub 操作](https://docs.github.com/en/actions)中，你可以添加一个额外的步骤来安装 Tuist，而在管理
Mise 的安装时，你可以使用 [mise-action](https://github.com/jdx/mise-action)，它可以抽象出 Mise 和
Tuist 的安装：

代码组
```yaml [Mise]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jdx/mise-action@v2
      - run: tuist build
```
```yaml [Homebrew]
name: test
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  lint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: brew install --formula tuist@x.y.z
      - run: tuist build
```
:::

::: 提示 我们建议在 Tuist 项目中使用`mise use --pin` 来跨环境固定 Tuist
版本。该命令将创建一个`.tool-versions` 文件，其中包含 Tuist 的版本：

## 身份验证 {#authentication}

在使用 <LocalizedLink href="/guides/features/cache">cache</LocalizedLink>
等服务器端功能时，你需要一种方法来验证从 CI 工作流到服务器的请求。为此，你可以运行以下命令生成一个项目范围内的令牌：

```bash
tuist project tokens create my-handle/MyApp
```

该命令将为项目生成一个令牌，其完整句柄为`my-account/my-project` 。在 CI 环境中设置环境变量`TUIST_CONFIG_TOKEN`
的值，确保将其配置为机密，以免暴露。

> [重要] CI 环境检测 Tuist 仅在检测到运行于 CI 环境时才使用令牌。如果未检测到您的 CI 环境，可以通过将环境变量`CI` 设置为`1`
> 来强制使用令牌。
