---
{
  "title": "継続的インテグレーション (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "CI ワークフローで Tuist を活用する方法を学びます。"
}
---
# 継続的インテグレーション（CI）{#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)ワークフローでTuistコマンドを実行するには、CI環境にTuistをインストールする必要があります。 

認証は任意ですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>などのサーバー側機能を利用する場合は必須です。 

以下のセクションでは、さまざまなCIプラットフォームでの設定例を紹介します。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行えます：

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
> **OIDCの設定**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。OIDCを動作させるには`permissions: id-token: write`が必要です。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`シークレットを使用することもできます。


> [!TIP]
> Tuistプロジェクトでは`mise use --pin`を使用して、環境間でTuistのバージョンを固定することを推奨します。このコマンドは、Tuistのバージョンを含む`.tool-versions`ファイルを作成します。


### Xcode Cloud {#xcode-cloud}

Xcodeプロジェクトを信頼できる情報源として使用する[Xcode Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールして必要なコマンド（例：`tuist generate`）を実行するための[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります：

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
> Xcode Cloudのワークフロー設定で`TUIST_TOKEN`環境変数を設定し、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用してください。


### CircleCI {#circleci}

[CircleCI](https://circleci.com)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行えます：

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
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。CircleCIのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行えます：

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
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリをTuistプロジェクトに接続</.localized_link>する必要があります。BitriseのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)では、ワークフローに追加のステップを加えてTuistをインストールできます：

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
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、`TUIST_TOKEN`という名前のシークレット環境変数として追加してください。

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
> Tuist InstallステップはHomebrewでTuistをインストールし、`tuist generate`を実行します。**Tuist Version**入力欄でバージョンを固定し、Tuist Commandsステップを追加して`tuist test`や`tuist build`などのコマンドを実行してください。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables)に`TUIST_TOKEN`という名前の変数として追加して、ビルド構成でそのグループを選択してください。ロックアイコンを使用して変数をシークレットとしてマークします。

## 実行レポート {#run-report}

Tuistが実行をアップロードすると、そのダッシュボードURLがログに出力されます。ログをスクレイピングせずにURLを取得するため（例：ジョブ失敗時にテストレポートリンクをSlackに投稿したり、独自ツールに取り込んだりする場合）には、`--run-report-path`（または`TUIST_RUN_REPORT_PATH`を設定）を`tuist test`、`tuist xcodebuild test`、あるいは`tuist xcodebuild build`に渡してください。実行のアップロード完了後、TuistはそのパスにJSONレポートを書き込みます：

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
| `runId` | 文字列 | 実行の一意な識別子。 |
| `status` | 文字列 | `"success"`または`"failure"`。 |
| `runURL` | 文字列 | 実行のダッシュボードURL。常に存在します。 |
| `testRunURL` | 文字列? | テスト実行のダッシュボードURL。コマンドがテストを実行した場合に存在します。 |
| `buildRunURL` | 文字列? | ビルド実行のダッシュボードURL。コマンドがビルドを実行した場合に存在します。 |
| `testRuns` | 配列 | スキームごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および`skippedTestModules`。テスト件数はテストケースの数であり、`skippedTests`は結果バンドルでスキップされたものとして報告された件数を示します。`skippedTestModules`は<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>によってスキップされたテストモジュールの数を示し、選択的テストが適用されなかった場合や実行がテストシャードの場合は省略されます。 |
| `buildRuns` | 配列 | スキームごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`と`buildRunURL`は独立しています：ビルドとテストの両方を行うコマンドは両方のURLを出力しますが、ログでは実行ごとに1つのURLしか出力できません。

> [!NOTE]
> **レポートの書き込みタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CI環境では自動的に行われます。パスは各実行の開始時にクリアされるため、レポートが生成されない実行では、前回の実行からの古いレポートが残るのではなく、何も残りません。

GitLab CIでは、[`dotenv`レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)を通じて後続のジョブにURLを公開するのが一般的な用途です：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
