---
{
  "title": "持續整合 (CI)",
  "titleTemplate": ":title · 自動化 · 指南 · Tuist",
  "description": "了解如何在你的 CI 工作流程中使用 Tuist。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

要喺你嘅 [持續整合](https://en.wikipedia.org/wiki/Continuous_integration) 工作流程入面執行 Tuist 指令，你需要喺 CI 環境安裝佢。 

驗證係可選嘅，但如果你想使用伺服器端功能例如 <.localized_link href="/guides/features/cache">快取</.localized_link>，就必須進行驗證。 

以下章節提供咗喺唔同 CI 平台點樣做嘅例子。

## 例子 {#examples}

### GitHub Actions {#github-actions}

喺 [GitHub Actions](https://docs.github.com/en/actions)，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 嚟進行安全、無需密鑰嘅驗證：

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
```yaml [Project token (Mise)]
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
```yaml [Project token (Homebrew)]
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
> **Oidc 設定**
>
> 喺使用 OIDC 驗證之前，你需要 <.localized_link href="/guides/integrations/gitforge/github">將你嘅 GitHub 儲存庫連接</.localized_link> 到你嘅 Tuist 專案。`permissions: id-token: write` 係 OIDC 運作所必需嘅。或者，你可以使用帶有 `TUIST_TOKEN` 密鑰嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


> [!TIP]
> 我哋建議喺你嘅 Tuist 專案中使用 `mise use --pin` 嚟固定跨環境嘅 Tuist 版本。呢個指令會建立一個包含 Tuist 版本嘅 `.tool-versions` 檔案。


### Xcode Cloud {#xcode-cloud}

喺 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)（以 Xcode 專案為單一事實來源），你需要添加一個 [克隆後](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 腳本來安裝 Tuist 並執行你需要嘅指令，例如 `tuist generate`：

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
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
<!-- -->
:::

> [!NOTE]
> **驗證**
>
> 透過喺你嘅 Xcode Cloud 工作流程設定中設定 `TUIST_TOKEN` 環境變數，來使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### CircleCI {#circleci}

喺 [CircleCI](https://circleci.com)，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 嚟進行安全、無需密鑰嘅驗證：

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
```yaml [Project token (Mise)]
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
> **驗證**
>
> 喺使用 OIDC 驗證之前，你需要 <.localized_link href="/guides/integrations/gitforge/github">將你嘅 GitHub 儲存庫連接</.localized_link> 到你嘅 Tuist 專案。CircleCI OIDC 令牌包含你已連接嘅 GitHub 儲存庫，Tuist 用佢嚟授權訪問你嘅專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變數嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### Bitrise {#bitrise}

喺 [Bitrise](https://bitrise.io)，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 嚟進行安全、無需密鑰嘅驗證：

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
```yaml [Project token (Mise)]
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
> **驗證**
>
> 喺使用 OIDC 驗證之前，你需要 <.localized_link href="/guides/integrations/gitforge/github">將你嘅 GitHub 儲存庫連接</.localized_link> 到你嘅 Tuist 專案。Bitrise OIDC 令牌包含你已連接嘅 GitHub 儲存庫，Tuist 用佢嚟授權訪問你嘅專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變數嘅 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。


### Codemagic {#codemagic}

喺 [Codemagic](https://codemagic.io)，你可以喺工作流程中添加額外步驟來安裝 Tuist：

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
          mise install # Installs the version from .mise.toml
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
> **驗證**
>
> 建立一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>，並將佢添加為名為 `TUIST_TOKEN` 嘅秘密環境變數。

### Appcircle {#appcircle}

喺 [Appcircle](https://appcircle.io)，你可以使用內置嘅 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 同 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 工作流程步驟，或者喺 **Git Clone** 步驟之後添加一個 **自定義腳本** 步驟來自行安裝 Tuist：

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
> Tuist Install 步驟會使用 Homebrew 安裝 Tuist 並執行 `tuist generate`。設定 **Tuist Version** 輸入以固定版本，然後添加 Tuist Commands 步驟來執行例如 `tuist test` 或 `tuist build` 嘅指令。

> [!NOTE]
> **驗證**
>
> 建立一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>，將佢作為名為 `TUIST_TOKEN` 嘅變數添加到 [環境變數組](https://docs.appcircle.io/build/build-environment-variables)，並喺你嘅建構設定中選擇該組。使用鎖定圖示將變數標記為秘密。

## 運行報告 {#run-report}

當 Tuist 上傳一次運行時，儀表板 URL 會打印到日誌中。要無需爬取日誌就獲取佢哋——例如當工作失敗時將測試報告連結發佈到 Slack，或者將運行數據餵送你自己的工具——請將 `--run-report-path`（或設定 `TUIST_RUN_REPORT_PATH`）傳遞給 `tuist test`、`tuist xcodebuild test` 或 `tuist xcodebuild build`。一旦運行上傳完成，Tuist 會將 JSON 報告寫入該路徑：

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

| 欄位 | 類型 | 描述 |
| - | - | - |
| `runId` | 字串 | 運行嘅唯一識別碼。 |
| `status` | 字串 | `"success"` 或 `"failure"`。 |
| `runURL` | 字串 | 該運行嘅儀表板 URL。一定存在。 |
| `testRunURL` | 字串? | 測試運行嘅儀表板 URL，當指令執行測試時出現。 |
| `buildRunURL` | 字串? | 建構運行嘅儀表板 URL，當指令進行建構時出現。 |
| `testRuns` | 陣列 | 每個 Scheme 嘅測試結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules` 同 `skippedTestModules`。測試計數係測試案例數量，而 `skippedTests` 計算結果套件報告為已跳過嘅案例。`skippedTestModules` 計算被 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 跳過嘅測試模組數量，如果無應用選擇性測試或者運行係測試分片，則會省略。 |
| `buildRuns` | 陣列 | 每個 Scheme 嘅建構結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL` 同 `buildRunURL` 係獨立嘅：同時進行建構同測試嘅指令會寫入兩者，但日誌做唔到——日誌每次運行只打印一個 URL。

> [!NOTE]
> **報告寫入時機**
>
> 報告只會為上傳到伺服器嘅運行寫入，這需要驗證並喺 CI 上自動發生。路徑會喺每次運行開始時清除，所以如果一次運行無產生報告，就唔會留下任何東西，而唔係留下之前運行嘅過時報告。

喺 GitLab CI，常見用法係透過 [`dotenv` 報告](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) 將 URL 暴露畀後續工作：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
