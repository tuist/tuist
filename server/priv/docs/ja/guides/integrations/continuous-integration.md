---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 継続的インテグレーション（CI） {#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)ワークフローでTuistコマンドを実行するには、CI環境にTuistをインストールする必要があります。 

認証はオプションですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>などのサーバーサイド機能を使用する場合は必須です。 

以下のセクションでは、さまざまなCIプラットフォームでの設定例を紹介します。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して、安全でシークレット不要の認証を行うことができます：

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
> **Oidcセットアップ**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。OIDCを動作させるには`permissions: id-token: write`が必要です。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`シークレットを使用することもできます。


> [!TIP]
> Tuistプロジェクトで`mise use --pin`を使用して、環境間でTuistのバージョンを固定することを推奨します。このコマンドは、Tuistのバージョンを含む`.tool-versions`ファイルを作成します。


### Xcode Cloud {#xcode-cloud}

Xcodeプロジェクトを信頼できる情報源として使用する[Xcode Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールし、必要なコマンド（例：`tuist generate`）を実行するために、[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります：

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
> **認証**
>
> Xcode Cloudのワークフロー設定で`TUIST_TOKEN`環境変数を設定することで、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用してください。


### CircleCI {#circleci}

[CircleCI](https://circleci.com)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して、安全でシークレット不要の認証を行うことができます：

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
> **認証**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。CircleCIのOIDCトークンには接続されたGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して、安全でシークレット不要の認証を行うことができます：

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
> **認証**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。BitriseのOIDCトークンには接続されたGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)では、ワークフローに追加のステップを追加してTuistをインストールできます：

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
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、それを`TUIST_TOKEN`という名前のシークレット環境変数として追加してください。

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)では、組み込みの[Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install)および[Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands)ワークフローステップを使用するか、**Git Clone**ステップの後に**Custom Script**ステップを追加して自分でTuistをインストールできます：

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
> **ワークフローステップ**
>
> Tuist InstallステップはHomebrewでTuistをインストールし、`tuist generate`を実行します。**Tuist Version**入力を設定してバージョンを固定し、その後Tuist Commandsステップを追加して`tuist test`や`tuist build`などのコマンドを実行します。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、それを`TUIST_TOKEN`という名前の変数として[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables)に追加し、ビルド構成でそのグループを選択してください。ロックアイコンを使用して変数をシークレットとしてマークします。

## 実行レポート {#run-report}

Tuistが実行をアップロードすると、そのダッシュボードURLがログに出力されます。ログをスクレイピングせずにURLを取得するため（例えば、ジョブが失敗したときにテストレポートリンクをSlackに投稿したり、独自ツールに実行データを送信したりする場合）には、`--run-report-path`（または`TUIST_RUN_REPORT_PATH`を設定）を`tuist test`、`tuist xcodebuild test`、または`tuist xcodebuild build`に渡します。Tuistは、実行がアップロードされると、そのパスにJSONレポートを書き込みます：

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

| フィールド | 型 | 説明 |
| - | - | - |
| `runId` | 文字列 | 実行の一意の識別子。 |
| `status` | 文字列 | `"success"`または`"failure"`。 |
| `runURL` | 文字列 | 実行のダッシュボードURL。常に存在します。 |
| `testRunURL` | 文字列? | テスト実行のダッシュボードURL。コマンドがテストを実行した場合に存在します。 |
| `buildRunURL` | 文字列? | ビルド実行のダッシュボードURL。コマンドがビルドを実行した場合に存在します。 |
| `testRuns` | 配列 | スキームごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および`skippedTestModules`。テスト数はテストケースの数であり、`skippedTests`は結果バンドルでスキップされたとして報告された数をカウントします。`skippedTestModules`は<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>によってスキップされたテストモジュールの数をカウントし、選択的テストが適用されなかった場合、または実行がテストシャードである場合は省略されます。 |
| `buildRuns` | 配列 | スキームごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`と`buildRunURL`は独立しています：ビルドとテストの両方を実行するコマンドは両方を出力しますが、ログではそれができません。ログは実行ごとに1つのURLしか出力しません。

> [!NOTE]
> **レポートが書き込まれるタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CIでは自動的に行われます。パスは各実行の開始時にクリアされるため、レポートを生成しない実行では、以前の実行からの古いレポートではなく、何も残されません。

GitLab CIでは、一般的な使用方法として、[`dotenv`レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)を使用して後続のジョブにURLを公開します：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
