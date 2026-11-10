---
{
  "title": "継続的インテグレーション (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Tuist を CI ワークフローで活用する方法を学びます。"
}
---
# 継続的インテグレーション（CI） {#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)ワークフローでTuistコマンドを実行するには、CI環境にTuistをインストールする必要があります。 

認証は任意ですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>などのサーバー側機能を使用する場合は必須です。 

以下のセクションでは、さまざまなCIプラットフォームでの設定例を紹介します。Onceは独自のネイティブなTuistプロバイダーを通じて接続するため、Tuist CLIは不要です。そのワークフローについては[Once](#once)をご覧ください。

## Once {#once}

<.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link>からプロバイダーとキャッシュバインディングをコミットしてください。[Onceのインストール手順](https://buildonce.dev/docs/guide/getting-started)に従ってジョブ内にOnceをインストールし、キャッシュ可能な作業を実行する前に認証を行います。

GitHub Actions、CircleCI、Bitriseは、OnceのヘッドレスOpenID Connectログインをサポートしています。<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>の説明に従って、リポジトリをTuistプロジェクトに接続してください。GitHub Actionsでは、identity-token権限を付与します。

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

ターゲットが必要とするツールチェーンを備えたOSを選択してください。`MyTarget`をあなたのターゲットに置き換え、既存のツールインストールワークフローを通じてOnceのバージョンを固定します。生成されたセッションは、ジョブ中のキャッシュアクセス、レポート作成、およびアーティファクト公開のために再利用されます。

他のプロバイダーでは、`TUIST_TOKEN`を必要な操作が許可された<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>に設定してください。CIのシークレットストアに保存し、`once.toml`やワークフローのソースコードには決して保存しないでください。そのトークンを使用する場合、対話型ログイン手順は不要です。

マルチワーカー構成の場合は、<.localized_link href="/guides/features/test-sharding/once">Onceテストシャーディング</.localized_link>の手順に従ってください。アプリケーションを公開するには、明示的な<.localized_link href="/guides/features/previews/once">Onceプレビュー公開</.localized_link>ステップを追加します。通常のビルドではプレビューは暗黙的に公開されません。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行うことができます。

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
> **OIDC設定**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。OIDCを動作させるには`permissions: id-token: write`が必要です。 alternatively、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`シークレットを使用することもできます。


> [!TIP]
> 環境間でTuistのバージョンを固定するために、Tuistプロジェクトで`mise use --pin`を使用することを推奨します。このコマンドは、`mise.toml`ファイル内のTuistバージョンを固定します。


### Xcode Cloud {#xcode-cloud}

Xcodeプロジェクトを信頼できる情報源として使用する[Xcode Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールして必要なコマンド（例えば`tuist generate`）を実行するための[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります。

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
> **認証**
>
> Xcode Cloudのワークフロー設定で`TUIST_TOKEN`環境変数を設定することで、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用します。


### CircleCI {#circleci}

[CircleCI](https://circleci.com)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行うことができます。

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
> **認証**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。CircleCIのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。 alternatively、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全かつシークレット不要の認証を行うことができます。

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
> **認証**
>
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。BitriseのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。 alternatively、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>と`TUIST_TOKEN`環境変数を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)では、Tuistをインストールするためにワークフローに追加のステップを加えることができます。

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
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、`TUIST_TOKEN`という名前のシークレット環境変数として追加します。

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)では、組み込みの[Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install)および[Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands)ワークフローステップを使用するか、**Git Clone**ステップの後に**Custom Script**ステップを追加して自分でTuistをインストールできます。

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
> Tuist InstallステップはHomebrewでTuistをインストールし、`tuist generate`を実行します。**Tuist Version**入力欄にバージョンを指定して固定し、その後Tuist Commandsステップを追加して`tuist test`や`tuist build`などのコマンドを実行します。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables)に`TUIST_TOKEN`という名前の変数として追加します。ビルド設定でそのグループを選択し、ロックアイコンを使って変数をシークレットとしてマークします。

## 実行レポート {#run-report}

Tuistが実行をアップロードすると、そのダッシュボードURLがログに出力されます。ログをスクレイピングせずにURLを取得するには（例：ジョブ失敗時にテストレポートリンクをSlackに投稿する場合や、独自ツールに取り込む場合）、`tuist test`、`tuist xcodebuild test`、または`tuist xcodebuild build`に`--run-report-path`を渡すか（あるいは`TUIST_RUN_REPORT_PATH`を設定します）。Tuistは実行のアップロード完了後、そのパスにJSONレポートを書き込みます。

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
| `testRuns` | 配列 | スキーマごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および`skippedTestModules`。テスト数はテストケースの数であり、`skippedTests`は結果バンドルでスキップされたと報告されたテストケースの数を示します。`skippedTestModules`は<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>によってスキップされたテストモジュールの数を示し、選択的テストが適用されない場合や実行がテストシャードである場合は省略されます。 |
| `buildRuns` | 配列 | スキーマごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`と`buildRunURL`は独立しています。ビルドとテストの両方を実行するコマンドは両方のURLを書き出しますが、ログではそれができません。ログは実行ごとに1つのURLしか出力しません。

> [!NOTE]
> **レポートが書き込まれるタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CI上では自動的に行われます。パスは各実行の開始時にクリアされるため、レポートを生成しない実行があっても、前回の実行による古いデータが残ることはありません。

GitLab CIでは、後のジョブにURLを公開するために[`dotenv`レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)を使用するのが一般的です。

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
