---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持續整合 (CI) {#continuous-integration-ci}

要在你的[持續整合](https://en.wikipedia.org/wiki/Continuous_integration)工作流程中執行 Tuist 指令，你需要在 CI 環境中安裝它。 

驗證是可選的，但如果你想使用伺服器端功能（例如 <.localized_link href="/guides/features/cache">快取</.localized_link>），則必須進行驗證。 

以下章節提供在不同 CI 平台上如何進行此操作的範例。

## 範例 {#examples}

### GitHub Actions {#github-actions}

在 [GitHub Actions](https://docs.github.com/en/actions) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 來進行安全且無需密鑰的驗證：

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
> 在使用 OIDC 驗證之前，你需要將 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link> 連接到你的 Tuist 專案。`permissions: id-token: write` 是 OIDC 運作所必需的。或者，你可以使用帶有 `TUIST_TOKEN` 密鑰的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


> [!TIP]
> 我們建議在你的 Tuist 專案中使用 `mise use --pin`，以便在各個環境中固定 Tuist 的版本。該指令將建立一個包含 Tuist 版本的 `.tool-versions` 檔案。


### Xcode Cloud {#xcode-cloud}

在 [Xcode Cloud](https://developer.apple.com/xcode-cloud/) 中（它以 Xcode 專案為真實來源），你需要添加一個 [克隆後](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) 腳本來安裝 Tuist 並執行你需要的指令，例如 `tuist generate`：

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
> 透過在 Xcode Cloud 工作流程設定中設定 `TUIST_TOKEN` 環境變數，使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### CircleCI {#circleci}

在 [CircleCI](https://circleci.com) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 來進行安全且無需密鑰的驗證：

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
> 在使用 OIDC 驗證之前，你需要將 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link> 連接到你的 Tuist 專案。CircleCI OIDC 權杖包含你連接的 GitHub 儲存庫，Tuist 會用它來授權存取你的專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變數的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### Bitrise {#bitrise}

在 [Bitrise](https://bitrise.io) 上，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 來進行安全且無需密鑰的驗證：

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
> 在使用 OIDC 驗證之前，你需要將 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link> 連接到你的 Tuist 專案。Bitrise OIDC 權杖包含你連接的 GitHub 儲存庫，Tuist 會用它來授權存取你的專案。或者，你可以使用帶有 `TUIST_TOKEN` 環境變數的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。


### Codemagic {#codemagic}

在 [Codemagic](https://codemagic.io) 中，你可以在工作流程中添加額外步驟來安裝 Tuist：

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
> 建立一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>，並將其添加為名為 `TUIST_TOKEN` 的保密環境變數。

### Appcircle {#appcircle}

在 [Appcircle](https://appcircle.io) 中，你可以使用內建的 [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) 和 [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) 工作流程步驟，或者在 **Git Clone** 步驟之後添加一個 **自訂腳本** 步驟來自行安裝 Tuist：

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
> Tuist Install 步驟會使用 Homebrew 安裝 Tuist 並執行 `tuist generate`。設定 **Tuist Version** 輸入以固定版本，然後添加 Tuist Commands 步驟來執行如 `tuist test` 或 `tuist build` 等指令。

> [!NOTE]
> **驗證**
>
> 建立一個 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>，將其作為名為 `TUIST_TOKEN` 的變數添加到 [環境變數群組](https://docs.appcircle.io/build/build-environment-variables)，並在你的建置組態中選擇該群組。使用鎖頭圖示將該變數標記為保密。

## 執行報告 {#run-report}

當 Tuist 上傳執行記錄時，其儀表板 URL 會列印到日誌中。若要在不抓取日誌的情況下獲取它們——例如在工作失敗時將測試報告連結發佈到 Slack，或將執行記錄饋送到你自己的工具鏈——請將 `--run-report-path`（或設定 `TUIST_RUN_REPORT_PATH`）傳遞給 `tuist test`、`tuist xcodebuild test` 或 `tuist xcodebuild build`。一旦執行記錄上傳完成，Tuist 會將 JSON 報告寫入該路徑：

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
| `runId` | 字串 | 執行的唯一識別碼。 |
| `status` | 字串 | `"success"` 或 `"failure"`。 |
| `runURL` | 字串 | 該執行的儀表板 URL。必定存在。 |
| `testRunURL` | 字串? | 測試執行的儀表板 URL，當指令執行測試時會出現。 |
| `buildRunURL` | 字串? | 建置執行的儀表板 URL，當指令進行建置時會出現。 |
| `testRuns` | 陣列 | 每個 Scheme 的測試結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules` 和 `skippedTestModules`。測試計數是指測試案例，而 `skippedTests` 計算結果套件報告為已跳過的案例。`skippedTestModules` 計算被 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 跳過的測試模組，當不適用選擇性測試或該執行是測試分片時則會省略。 |
| `buildRuns` | 陣列 | 每個 Scheme 的建置結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL` 和 `buildRunURL` 是獨立的：同時進行建置和測試的指令會寫入兩者，而日誌無法做到這一點——它們每次執行只列印一個 URL。

> [!NOTE]
> **報告寫入時機**
>
> 報告僅針對上傳至伺服器的執行記錄寫入，這需要驗證並在 CI 上自動發生。路徑會在每次執行開始時清除，因此如果執行沒有產生報告，就不會留下任何內容，而不是留下之前執行的過時報告。

在 GitLab CI 上，常見用法是透過 [`dotenv` 報告](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) 將 URL 公開給後續的工作：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
