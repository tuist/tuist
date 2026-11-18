---
{
  "title": "持續整合 (CI)",
  "titleTemplate": ":title · 自動化 · 指南 · Tuist",
  "description": "了解如何在 CI 工作流程中使用 Tuist。"
}
---
# 持續整合 (CI) {#continuous-integration-ci}

若要在你的[持續整合](https://en.wikipedia.org/wiki/Continuous_integration)工作流程中執行 Tuist 指令，你需要在 CI 環境中安裝它。 

驗證為可選項目，但若想使用如<.localized_link href="/guides/features/cache">快取</.localized_link>等伺服器端功能則為必要。 

以下章節提供在不同 CI 平台上進行設定的範例。Once 透過其原生的 Tuist 提供者進行連線；它不需要 Tuist CLI。請參閱[Once](#once)以了解該工作流程。

## Once {#once}

提交來自<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>的提供者與快取綁定。使用[Once 的安裝說明](https://buildonce.dev/docs/guide/getting-started)在作業中安裝 Once，然後在執行可快取的工作前進行驗證。

GitHub Actions、CircleCI 和 Bitrise 支援 Once 的無頭式 OpenID Connect 登入。依照<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>中的說明，將儲存庫連接至你的 Tuist 專案。在 GitHub Actions 上，授予 identity-token 權限：

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

選擇具備你的目標所需工具鏈的作業系統。將`MyTarget`替換為你的目標，並透過現有的工具安裝工作流程固定 Once 版本。產生的工作階段會在作業期間重複用於快取存取、報告和構件發布。

在其他提供者上，將`TUIST_TOKEN`設定為已授權執行所需操作的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。將其儲存在 CI 密鑰儲存庫中，切勿存放在`once.toml`或工作流程原始碼中。使用該權杖時，不需要互動式登入步驟。

對於多工作節點套件，請遵循<.localized_link href="/guides/features/test-sharding/once">Once 測試分片</.localized_link>。若要發布應用程式，請新增明確的<.localized_link href="/guides/features/previews/once">Once 預覽發布</.localized_link>步驟。一般建置不會隱含發布預覽。

## 範例 {#examples}

### GitHub Actions {#github-actions}

在[GitHub Actions](https://docs.github.com/en/actions)上，你可以使用<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>進行安全且無需密鑰的驗證：

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
> 在使用 OIDC 驗證之前，你需要將<.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link>連接至你的 Tuist 專案。`permissions: id-token: write`是 OIDC 運作所需的條件。或者，你可以使用帶有`TUIST_TOKEN`密鑰的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


> [!TIP]
> 我們建議在你的 Tuist 專案中使用`mise use --pin`，以便在各個環境中固定 Tuist 的版本。此指令會將 Tuist 的版本固定在你的`mise.toml`檔案中。


### Xcode Cloud {#xcode-cloud}

在[Xcode Cloud](https://developer.apple.com/xcode-cloud/)中（它以 Xcode 專案為單一事實來源），你需要新增一個[克隆後](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)腳本來安裝 Tuist 並執行你需要的指令，例如`tuist generate`：

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
> **驗證**
>
> 透過在 Xcode Cloud 工作流程設定中設定`TUIST_TOKEN`環境變數，使用<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### CircleCI {#circleci}

在[CircleCI](https://circleci.com)上，你可以使用<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>進行安全且無需密鑰的驗證：

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
> **驗證**
>
> 在使用 OIDC 驗證之前，你需要將<.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link>連接至你的 Tuist 專案。CircleCI OIDC 權杖包含你已連接的 GitHub 儲存庫，Tuist 會用它來授權對你專案的存取。或者，你可以使用帶有`TUIST_TOKEN`環境變數的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### Bitrise {#bitrise}

在[Bitrise](https://bitrise.io)上，你可以使用<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>進行安全且無需密鑰的驗證：

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
> **驗證**
>
> 在使用 OIDC 驗證之前，你需要將<.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link>連接至你的 Tuist 專案。Bitrise OIDC 權杖包含你已連接的 GitHub 儲存庫，Tuist 會用它來授權對你專案的存取。或者，你可以使用帶有`TUIST_TOKEN`環境變數的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### Codemagic {#codemagic}

在[Codemagic](https://codemagic.io)中，你可以在工作流程中新增一個額外步驟來安裝 Tuist：

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
> **驗證**
>
> 建立一個<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>，並將其新增為名為`TUIST_TOKEN`的密鑰環境變數。

### Appcircle {#appcircle}

在[Appcircle](https://appcircle.io)中，你可以使用內建的[Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install)和[Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands)工作流程步驟，或在**Git Clone**步驟之後新增一個**自訂腳本**步驟來自行安裝 Tuist：

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
> Tuist Install 步驟會使用 Homebrew 安裝 Tuist 並執行`tuist generate`。設定**Tuist Version**輸入以固定版本，然後新增 Tuist Commands 步驟來執行如`tuist test`或`tuist build`等指令。

> [!NOTE]
> **驗證**
>
> 建立一個<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>，將其新增為[環境變數群組](https://docs.appcircle.io/build/build-environment-variables)中名為`TUIST_TOKEN`的變數，並在建置設定中選取該群組。使用鎖頭圖示將該變數標記為密鑰。

## 執行報告{#run-report}

當 Tuist 上傳執行紀錄時，其儀表板網址會列印至日誌中。若要在不解析日誌的情況下取得這些網址（例如在工作失敗時將測試報告連結發布至 Slack，或將執行資料饋送至你自己的工具鏈），請將`--run-report-path`（或設定`TUIST_RUN_REPORT_PATH`）傳遞給`tuist test`、`tuist xcodebuild test`或`tuist xcodebuild build`。Tuist 會在執行上傳完成後，將 JSON 報告寫入該路徑：

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

| 欄位 | 類型 | 說明 |
| - | - | - |
| `runId` | 字串 | 執行的唯一識別碼。 |
| `status` | 字串 | `"success"`或`"failure"`。 |
| `runURL` | 字串 | 該執行的儀表板網址。一律存在。 |
| `testRunURL` | 字串? | 測試執行的儀表板網址，在指令執行測試時存在。 |
| `buildRunURL` | 字串? | 建置執行的儀表板網址，在指令執行建置時存在。 |
| `testRuns` | 陣列 | 每個 Scheme 的測試結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`和`skippedTestModules`。測試計數為測試案例數量，而`skippedTests`計數結果套件回報為已跳過的案例。`skippedTestModules`計數被<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>跳過的測試模組數量；若未套用選擇性測試或該執行為測試分片，則省略此欄位。 |
| `buildRuns` | 陣列 | 每個 Scheme 的建置結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`與`buildRunURL`相互獨立：同時執行建置與測試的指令會寫入兩者，但日誌無法做到這一點——日誌每項執行僅列印一個網址。

> [!NOTE]
> **報告寫入時機**
>
> 報告僅針對已上傳至伺服器的執行進行寫入，這需要驗證且在 CI 上會自動發生。每次執行開始時都會清除該路徑，因此若某次執行未產生報告，則不會留下任何內容，而非保留先前執行的過時報告。

在 GitLab CI 上，常見用法是透過[`dotenv`報告](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)向後續工作公開網址：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
