---
{
  "title": "持续集成 (CI)",
  "titleTemplate": ":title · 自动化 · 指南 · Tuist",
  "description": "了解如何在 CI 工作流中使用 Tuist。"
}
---
# 持续集成 (CI) {#continuous-integration-ci}

要在你的 [持续集成](https://en.wikipedia.org/wiki/Continuous_integration) 工作流中运行 Tuist 命令，你需要在 CI 环境中安装它。 

身份验证是可选的，但如果你要使用服务器端功能（如 <.localized_link href="/guides/features/cache">缓存</.localized_link>），则必须进行身份验证。 

以下部分提供了在不同 CI 平台上执行此操作的示例。Once 通过其原生的 Tuist 提供程序进行连接；它不需要 Tuist CLI。有关该工作流，请参阅 [Once](#once)。

## Once {#once}

提交来自 <.localized_link href="/guides/get-started/once-project">开始使用 Once</.localized_link> 的提供程序和缓存绑定。使用 [Once 的安装说明](https://buildonce.dev/docs/guide/getting-started) 在作业中安装 Once，然后在运行可缓存的工作之前进行身份验证。

GitHub Actions、CircleCI 和 Bitrise 支持 Once 的无头 OpenID Connect 登录。按照 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link> 中的描述，将存储库连接到你的 Tuist 项目。在 GitHub Actions 上，授予 identity-token 权限：

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2
      # Pin Once in your repository's mise.toml.
      - run: once auth login --provider tuist --no-browser
      - run: once build MyTarget
      - run: once test
```

选择具有目标所需工具链的操作系统。将 `MyTarget` 替换为你的目标，并通过现有的工具安装工作流固定 Once。生成的会话将在作业期间重用于缓存访问、报告和构件发布。

在其他提供程序上，将 `TUIST_TOKEN` 设置为有权执行所需操作的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。将其存储在 CI 密钥存储中，切勿存储在 `once.toml` 或工作流源代码中。使用该令牌时不需要交互式登录步骤。

对于多工作者套件，请遵循 <.localized_link href="/guides/features/test-sharding/once">Once 测试分片</.localized_link>。要发布应用程序，请添加显式的 <.localized_link href="/guides/features/previews/once">Once 预览发布</.localized_link> 步骤。普通构建不会隐式发布预览。

## 示例 {#examples}

### GitHub Actions {#github-actions}

在 [GitHub Actions](https://docs.github.com/en/actions) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link> 进行安全且无需秘密的身份验证：

::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Account token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Account token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **OIDC 设置**
>
> 在使用 OIDC 身份验证之前，你需要将 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 存储库</.localized_link> 连接到你的 Tuist 项目。`permissions: id-token: write` 是 OIDC 正常工作所必需的。或者，你可以使用带有 `TUIST_TOKEN` 秘密的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。


> [!TIP]
> 我们建议在你的 Tuist 项目中使用 `mise use --pin` 来跨环境固定 Tuist 的版本。该命令会将 Tuist 的版本固定在 `mise.toml` 文件中。


### Xcode Cloud {#xcode-cloud}

在 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)（它使用 Xcode 项目作为事实来源）中，你需要添加一个 [克隆后](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 脚本来安装 Tuist 并运行你需要的命令，例如 `tuist generate`：

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from mise.toml

# Runs the version of Tuist indicated in the mise.toml file
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

> [!NOTE]
> **身份验证**
>
> 通过在 Xcode Cloud 工作流设置中设置 `TUIST_TOKEN` 环境变量来使用 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。


### CircleCI {#circleci}

在 [CircleCI](https://circleci.com) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link> 进行安全且无需秘密的身份验证：

::: code-group
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **身份验证**
>
> 在使用 OIDC 身份验证之前，你需要将 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 存储库</.localized_link> 连接到你的 Tuist 项目。CircleCI OIDC 令牌包含你连接的 GitHub 存储库，Tuist 使用它来授权对你项目的访问。或者，你可以使用带有 `TUIST_TOKEN` 环境变量的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。


### Bitrise {#bitrise}

在 [Bitrise](https://bitrise.io) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link> 进行安全且无需秘密的身份验证：

::: code-group
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **身份验证**
>
> 在使用 OIDC 身份验证之前，你需要将 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 存储库</.localized_link> 连接到你的 Tuist 项目。Bitrise OIDC 令牌包含你连接的 GitHub 存储库，Tuist 使用它来授权对你项目的访问。或者，你可以使用带有 `TUIST_TOKEN` 环境变量的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。


### Codemagic {#codemagic}

在 [Codemagic](https://codemagic.io) 中，你可以向工作流添加额外步骤以安装 Tuist：

::: code-group
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **身份验证**
>
> 创建一个 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>，并将其添加为名为 `TUIST_TOKEN` 的秘密环境变量。

### Appcircle {#appcircle}

在 [Appcircle](https://appcircle.io) 中，你可以使用内置的 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 和 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 工作流步骤，或者在 **Git Clone** 步骤之后添加一个 **自定义脚本** 步骤来自行安装 Tuist：

::: code-group
```bash [Mise]
cd $AC_REPOSITORY_DIR
curl https://mise.jdx.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mise install
mise exec -- tuist setup cache
```
```bash [Homebrew]
cd $AC_REPOSITORY_DIR
brew install --formula tuist@x.y.z
tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **工作流步骤**
>
> Tuist Install 步骤通过 Homebrew 安装 Tuist 并运行 `tuist generate`。设置 **Tuist Version** 输入以固定版本，然后添加一个 Tuist Commands 步骤来运行诸如 `tuist test` 或 `tuist build` 之类的命令。

> [!NOTE]
> **身份验证**
>
> 创建一个 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>，将其作为名为 `TUIST_TOKEN` 的变量添加到 [环境变量组](https://docs.appcircle.io/build/build-environment-variables) 中，并在构建配置中选择该组。使用锁图标将该变量标记为秘密。

## 运行报告 {#run-report}

当 Tuist 上传运行时，其仪表板 URL 会打印到日志中。若要在不抓取日志的情况下获取这些 URL——例如在作业失败时将测试报告链接发布到 Slack，或将运行数据馈送到你自己的工具链中——请将 `--run-report-path`（或设置 `TUIST_RUN_REPORT_PATH`）传递给 `tuist test`、`tuist xcodebuild test` 或 `tuist xcodebuild build`。一旦运行上传完成，Tuist 会将 JSON 报告写入该路径：

```json
{
  "runId": "0193f8c1-...",
  "status": "success",
  "runURL": "https://tuist.dev/acme/app/runs/0193f8c1-...",
  "testRunURL": "https://tuist.dev/acme/app/tests/test-runs/...",
  "buildRunURL": "https://tuist.dev/acme/app/builds/build-runs/...",
  "testRuns": [
    {
      "scheme": "App",
      "succeeded": true,
      "totalTests": 42,
      "skippedTests": 0,
      "ranTests": 42,
      "failedTestNames": [],
      "ranTestModules": 3,
      "skippedTestModules": 5
    }
  ],
  "buildRuns": [
    { "scheme": "App", "succeeded": true, "durationInSeconds": 12.3 }
  ]
}
```

| 字段 | 类型 | 描述 |
| - | - | - |
| `runId` | 字符串 | 运行的唯一标识符。 |
| `status` | 字符串 | `"success"` 或 `"failure"`。 |
| `runURL` | 字符串 | 该运行的仪表板 URL。始终存在。 |
| `testRunURL` | 字符串？ | 测试运行的仪表板 URL，在命令执行测试时存在。 |
| `buildRunURL` | 字符串？ | 构建运行的仪表板 URL，在命令执行构建时存在。 |
| `testRuns` | 数组 | 按 Scheme 划分的测试结果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules` 和 `skippedTestModules`。测试计数针对的是测试用例，`skippedTests` 统计结果包中报告为跳过的用例。`skippedTestModules` 统计被 <.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link> 跳过的测试模块，当不适用选择性测试或运行为测试分片时省略此项。 |
| `buildRuns` | 数组 | 按 Scheme 划分的构建结果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL` 和 `buildRunURL` 相互独立：同时执行构建和测试的命令会写入两者，而日志无法做到这一点——它们每次运行只打印一个 URL。

> [!NOTE]
> **报告写入时机**
>
> 报告仅针对上传到服务器的运行写入，这需要身份验证并在 CI 上自动发生。每次运行开始时都会清除该路径，因此未生成报告的运行不会留下任何内容，而不是保留之前运行的过时报告。

在 GitLab CI 上，常见的用法是通过 [`dotenv` 报告](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) 向后续作业公开 URL：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
