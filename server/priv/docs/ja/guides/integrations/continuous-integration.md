---
{
  "title": "継続的インテグレーション (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "CIワークフローでTuistを使用する方法を学びます。"
}
---
# 継続的インテグレーション（CI）{#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)ワークフローでTuistコマンドを実行するには、CI環境にTuistをインストールする必要があります。 

認証はオプションですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>などのサーバーサイド機能を使用する場合は必須です。 

以下のセクションでは、さまざまなCIプラットフォームでの設定例を示します。Onceは独自のネイティブなTuistプロバイダーを通じて接続するため、Tuist CLIは不要です。そのワークフローについては[Once](#once)をご覧ください。

## Once {#once}

<.localized_link href="/guides/get-started/once-project">Onceを使い始める</.localized_link>からプロバイダーとキャッシュのバインディングをコミットしてください。[Onceのインストール手順](https://buildonce.dev/docs/guide/getting-started)に従ってジョブ内にOnceをインストールし、キャッシュ可能な作業を実行する前に認証を行います。

GitHub Actions、CircleCI、BitriseはOnceのヘッドレスOpenID Connectログインをサポートしています。<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>の説明に従って、リポジトリをTuistプロジェクトに接続してください。GitHub Actionsでは、identity-token権限を付与します：

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

ターゲットが必要とするツールチェーンを含むOSを選択してください。`MyTarget`を自分のターゲットに置き換え、既存のツールインストールワークフローを通じてOnceのバージョンを固定します。 resultingセッションは、ジョブ中のキャッシュアクセス、レポート作成、アーティファクト公開のために再利用されます。

他のプロバイダーでは、`TUIST_TOKEN`に必要な操作が許可された<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を設定します。このトークンはCIのシークレットストアに保存し、`once.toml`やワークフローのソースコードには決して含めないでください。そのトークンを使用する場合、対話的なログインステップは不要です。

マルチワーカー構成の場合は、<.localized_link href="/guides/features/test-sharding/once">Onceテストシャーディング</.localized_link>に従ってください。アプリケーションを公開するには、明示的な<.localized_link href="/guides/features/previews/once">Onceプレビュー公開</.localized_link>ステップを追加します。通常のビルドではプレビューは暗黙的に公開されません。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全でシークレット不要の認証を行うことができます：

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
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。OIDCを動作させるには`permissions: id-token: write`が必要です。Tuist 4.218.0以降では、CLIが最初のリクエスト時にIDトークンを交換するため、ワークフローに`tuist auth login`ステップは不要です。それ以前のバージョンでは、他のTuistコマンドの前に`tuist auth login`を実行してください。 alternatively、`TUIST_TOKEN`シークレットと共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


> [!TIP]
> 環境間でTuistのバージョンを固定するため、Tuistプロジェクトで`mise use --pin`を使用することを推奨します。このコマンドは`mise.toml`ファイル内でTuistのバージョンを固定します。


### Xcode Cloud {#xcode-cloud}

Xcodeプロジェクトを信頼できる情報源として使用する[Xcode Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールして必要なコマンド（例：`tuist generate`）を実行するための[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります：

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
> Xcode Cloudのワークフロー設定で`TUIST_TOKEN`環境変数を設定し、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用します。


### CircleCI {#circleci}

[CircleCI](https://circleci.com)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全でシークレット不要の認証を行うことができます：

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
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。CircleCIのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。Tuist 4.218.0以降では、CLIが最初のリクエスト時にIDトークンを交換するため、`tuist auth login`ステップは不要です。それ以前のバージョンでは、他のTuistコマンドの前に`mise exec -- tuist auth login`を実行してください。 alternatively、`TUIST_TOKEN`環境変数と共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC認証</.localized_link>を使用して安全でシークレット不要の認証を行うことができます：

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
> OIDC認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHubリポジトリを接続</.localized_link>してTuistプロジェクトに関連付ける必要があります。BitriseのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを承認します。Tuist 4.218.0以降では、CLIが最初のリクエスト時にIDトークンを交換するため、`tuist auth login`ステップは不要です。それ以前のバージョンでは、他のTuistコマンドの前に`mise exec -- tuist auth login`を実行してください。 alternatively、`TUIST_TOKEN`環境変数と共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)では、Tuistをインストールするためにワークフローに追加のステップを加えることができます：

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
> Tuist InstallステップはHomebrewでTuistをインストールし、`tuist generate`を実行します。**Tuist Version**入力欄でバージョンを固定し、その後Tuist Commandsステップを追加して`tuist test`や`tuist build`などのコマンドを実行します。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、それを[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables)内の`TUIST_TOKEN`という名前の変数として追加します。ビルド構成でそのグループを選択してください。ロックアイコンを使用して、その変数をシークレットとしてマークします。

## xcodebuildの出力フォーマット {#xcodebuild-output-formatting}

`tuist build`、`tuist test`、`tuist xcodebuild build`、および`tuist xcodebuild test`は、[xcbeautify](https://github.com/cpisciotta/xcbeautify)のフォーマッタを使用して`xcodebuild`の出力を整形するため、これらのコマンドを手動でxcbeautifyにパイプする必要はありません。GitHub Actionsでは、`GITHUB_ACTIONS`環境変数を通じて検出され、TuistはxcbeautifyのGitHub Actionsレンダラーを使用します。これにより、コンパイラの警告、エラー、テストの失敗が実行サマリーとプルリクエストのアノテーションとして表示されます。それ以外の場所ではターミナルレンダラーを使用し、出力がパイプされていない場合や`NO_COLOR`が設定されていない限り色付きで表示されます。

明確なエラーなしでビルドが失敗した場合など、`xcodebuild`の未整形の出力を表示するには`--verbose`を渡します。

ジョブがTuistを経由せず直接`xcodebuild`を呼び出す場合は、手動でxcbeautifyにパイプし、`pipefail`を設定して、ビルドが失敗してもステップが失敗するようにします：

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## 実行レポート {#run-report}

Tuistが実行をアップロードすると、そのダッシュボードURLがログに出力されます。ログをスクレイピングせずにURLを取得したい場合（例：ジョブが失敗した際にテストレポートのリンクをSlackに投稿する場合や、独自ツールに入力する場合）には、`tuist test`、`tuist xcodebuild test`、または`tuist xcodebuild build`に`--run-report-path`を渡すか（あるいは`TUIST_RUN_REPORT_PATH`を設定します）。Tuistは実行がアップロードされると、そのパスにJSONレポートを書き込みます：

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
| `testRuns` | 配列 | スキームごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および`skippedTestModules`。テスト数はテストケースの数であり、`skippedTests`は結果バンドルでスキップされたものとして報告された数をカウントします。`skippedTestModules`は<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>によってスキップされたテストモジュールの数をカウントし、選択的テストが適用されなかった場合や実行がテストシャードである場合は省略されます。 |
| `buildRuns` | 配列 | スキームごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`と`buildRunURL`は独立しています：ビルドとテストの両方を行うコマンドは両方のURLを書き込みますが、ログではそれができません（ログは実行ごとに1つのURLのみを出力します）。

> [!NOTE]
> **レポートが書き込まれるタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CI上では自動的に行われます。パスは各実行の開始時にクリアされるため、レポートを生成しない実行があった場合でも、前回の実行からの古いデータが残ることはありません。

GitLab CIでは、後続のジョブに対してURLを公開するために[`dotenv`レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)を使用するのが一般的です：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
