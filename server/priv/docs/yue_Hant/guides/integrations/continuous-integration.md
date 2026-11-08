---
{
  "title": "持續整合 (CI)",
  "titleTemplate": ":title · 自動化 · 指南 · Tuist",
  "description": "了解如何在 CI 工作流程中使用 Tuist。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

要喺你嘅 [持續整合](https://en.wikipedia.org/wiki/Continuous_integration) 工作流程入面執行 Tuist 指令，你需要喺 CI 環境安裝佢。 

認證係可選嘅，但如果你想使用伺服器端功能例如 <.localized_link href="/guides/features/cache">快取</.localized_link>，就必須進行認證。 

以下章節提供咗喺唔同 CI 平台點樣做嘅例子。Once 透過佢自己原生嘅 Tuist 提供者連接；佢唔需要 Tuist CLI。有關該工作流程，請參閱 [Once](#once)。

## Once {#once}

提交來自 <.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link> 嘅提供者同快取綁定。使用 [Once 嘅安裝說明](https://buildonce.dev/docs/guide/getting-started) 喺任務中安裝 Once，然後喺執行可快取工作之前進行認證。

GitHub Actions、CircleCI 同 Bitrise 支援 Once 嘅無頭 OpenID Connect 登入。按照 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認證</.localized_link> 中所述，將儲存庫連接到你嘅 Tuist 專案。喺 GitHub Actions 上，授予 identity-token 權限：

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

選擇一個擁有你目標所需工具鏈嘅作業系統。將 `MyTarget` 替換為你嘅目標，並透過你現有嘅工具安裝工作流程來固定 Once 版本。產生嘅工作階段會喺任務期間重用，用於快取存取、報告同產物發布。

喺其他提供者上，將 `TUIST_TOKEN` 設置為一個已授權執行你需要操作嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。將佢儲存喺 CI 秘密儲存區，切勿儲存喺 `once.toml` 或工作流程原始碼中。使用該令牌時不需要互動式登入步驟。

對於多工作節點套件，請遵循 <.localized_link href="/guides/features/test-sharding/once">Once 測試分片</.localized_link>。要發布應用程式，請添加一個明確嘅 <.localized_link href="/guides/features/previews/once">Once 預覽發布</.localized_link> 步驟。普通構建不會隱式發布預覽。

## 例子 {#examples}

### GitHub Actions {#github-actions}

喺 [GitHub Actions](https://docs.github.com/en/actions) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認證</.localized_link> 進行安全、無需秘密金鑰嘅認證：

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
> **OIDC 設定**
>
> 喺使用 OIDC 認證之前，你需要將你嘅 GitHub 儲存庫 <.localized_link href="/guides/integrations/gitforge/github">連接</.localized_link> 到你嘅 Tuist 專案。`permissions: id-token: write` 係 OIDC 運作所必需嘅。或者，你可以使用帶有 `TUIST_TOKEN` 秘密金鑰嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


> [!TIP]
> 我哋建議喺你嘅 Tuist 專案中使用 `mise use --pin` 來跨環境固定 Tuist 版本。該命令會喺你嘅 `mise.toml` 文件中固定 Tuist 版本。


### Xcode Cloud {#xcode-cloud}

喺 [Xcode Cloud](https://developer.apple.com/xcode-cloud/) 中（佢使用 Xcode 專案作為單一事實來源），你需要添加一個 [克隆後](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 腳本來安裝 Tuist 並執行你需要嘅指令，例如 `tuist generate`：

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
> **認證**
>
> 透過喺你嘅 Xcode Cloud 工作流程設定中設置 `TUIST_TOKEN` 環境變量來使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### CircleCI {#circleci}

喺 [CircleCI](https://circleci.com) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認證</.localized_link> 進行安全、無需秘密金鑰嘅認證：

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
> **認證**
>
> 喺使用 OIDC 認證之前，你需要將你嘅 GitHub 儲存庫 <.localized_link href="/guides/integrations/gitforge/github">連接</.localized_link> 到你嘅 Tuist 專案。CircleCI OIDC 令牌包含你連接嘅 GitHub 儲存庫，Tuist 用佢來授權訪問你嘅專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變量嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### Bitrise {#bitrise}

喺 [Bitrise](https://bitrise.io) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認證</.localized_link> 進行安全、無需秘密金鑰嘅認證：

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
> **認證**
>
> 喺使用 OIDC 認證之前，你需要將你嘅 GitHub 儲存庫 <.localized_link href="/guides/integrations/gitforge/github">連接</.localized_link> 到你嘅 Tuist 專案。Bitrise OIDC 令牌包含你連接嘅 GitHub 儲存庫，Tuist 用佢來授權訪問你嘅專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變量嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### Codemagic {#codemagic}

喺 [Codemagic](https://codemagic.io) 中，你可以喺工作流程中添加一個額外步驟來安裝 Tuist：

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
> **認證**
>
> 創建一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link> 並將佢添加為名為 `TUIST_TOKEN` 嘅秘密環境變量。

### Appcircle {#appcircle}

喺 [Appcircle](https://appcircle.io) 中，你可以使用內置嘅 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 同 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 工作流程步驟，或者喺 **Git Clone** 步驟之後添加一個 **自定義腳本** 步驟來自行安裝 Tuist：

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
> **工作流程步驟**
>
> Tuist Install 步驟會使用 Homebrew 安裝 Tuist 並執行 `tuist generate`。設置 **Tuist Version** 輸入以固定版本，然後添加一個 Tuist Commands 步驟來運行例如 `tuist test` 或 `tuist build` 等指令。

> [!NOTE]
> **認證**
>
> 創建一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>，將其作為名為 `TUIST_TOKEN` 的變量添加到 [環境變量組](https://docs.appcircle.io/build/build-environment-variables) 中，並在你的構建配置中選擇該組。使用鎖定圖標將該變量標記為秘密。

## 運行報告 {#run-report}

當 Tuist 上傳一次運行時，其儀表板 URL 會打印到日誌中。若要無需抓取日誌即可獲取這些 URL（例如在工作失敗時將測試報告鏈接發布到 Slack，或將運行數據饋送到你自己的工具中），請將 `--run-report-path`（或設置 `TUIST_RUN_REPORT_PATH`）傳遞給 `tuist test`、`tuist xcodebuild test` 或 `tuist xcodebuild build`。一旦運行上傳完成，Tuist 會將 JSON 報告寫入該路徑：

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

| 字段 | 類型 | 描述 |
| - | - | - |
| `runId` | 字符串 | 運行的唯一標識符。 |
| `status` | 字符串 | `"success"` 或 `"failure"`。 |
| `runURL` | 字符串 | 運行的儀表板 URL。始終存在。 |
| `testRunURL` | 字符串？ | 測試運行的儀表板 URL，在命令運行測試時存在。 |
| `buildRunURL` | 字符串？ | 構建運行的儀表板 URL，在命令進行構建時存在。 |
| `testRuns` | 數組 | 每個 Scheme 的測試結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules` 和 `skippedTestModules`。測試計數指的是測試用例，而 `skippedTests` 統計結果包報告為跳過的測試用例。`skippedTestModules` 統計被 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 跳過的測試模塊，當不適用選擇性測試或該運行是測試分片時則省略此字段。 |
| `buildRuns` | 數組 | 每個 Scheme 的構建結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL` 和 `buildRunURL` 是獨立的：同時進行構建和測試的命令會寫入兩者，而日誌無法做到這一點——日誌每次運行只打印一個 URL。

> [!NOTE]
> **報告寫入時機**
>
> 報告僅針對上傳到服務器的運行寫入，這需要認證並在 CI 上自動發生。該路徑在每次運行開始時會被清除，因此如果一次運行沒有產生報告，則不會留下任何內容，而不是留下之前運行的過時報告。

在 GitLab CI 上，常見用法是通過 [`dotenv` 報告](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) 向後續作業暴露 URL：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
