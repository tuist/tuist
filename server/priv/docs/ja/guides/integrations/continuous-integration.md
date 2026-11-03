---
{
  "title": "継続的インテグレーション (CI)",
  "titleTemplate": ":title · 自動化 · ガイド · Tuist",
  "description": "CI ワークフローで Tuist を使用する方法を学びます。"
}
---
# 継続的インテグレーション (CI) {#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration) ワークフローで Tuist コマンドを実行するには、CI 環境に Tuist をインストールする必要があります。 

認証は任意ですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link> などのサーバー側機能を使用する場合は必須です。 

以下のセクションでは、さまざまな CI プラットフォームでの設定例を紹介します。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions) では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link> を使用して、安全かつシークレット不要の認証を行えます。

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
> **OIDC のセットアップ**
>
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを Tuist プロジェクトに接続</.localized_link> する必要があります。OIDC を動作させるには `permissions: id-token: write` が必要です。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> と `TUIST_TOKEN` シークレットを使用することもできます。


> [!TIP]
> Tuist プロジェクトで `mise use --pin` を使用して、環境間で Tuist のバージョンを固定することを推奨します。このコマンドは、Tuist のバージョンを含む `.tool-versions` ファイルを作成します。


### Xcode Cloud {#xcode-cloud}

Xcode プロジェクトを信頼できる情報源として使用する [Xcode Cloud](https://developer.apple.com/xcode-cloud/) では、Tuist をインストールし、必要なコマンド（例：`tuist generate`）を実行するための [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) スクリプトを追加する必要があります。

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
> Xcode Cloud のワークフロー設定で `TUIST_TOKEN` 環境変数を設定し、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を使用します。


### CircleCI {#circleci}

[CircleCI](https://circleci.com) では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link> を使用して、安全かつシークレット不要の認証を行えます。

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
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを Tuist プロジェクトに接続</.localized_link> する必要があります。CircleCI の OIDC トークンには接続済みの GitHub リポジトリが含まれており、Tuist はこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> と `TUIST_TOKEN` 環境変数を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io) では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link> を使用して、安全かつシークレット不要の認証を行えます。

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
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを Tuist プロジェクトに接続</.localized_link> する必要があります。Bitrise の OIDC トークンには接続済みの GitHub リポジトリが含まれており、Tuist はこれを使用してプロジェクトへのアクセスを承認します。代わりに、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> と `TUIST_TOKEN` 環境変数を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io) では、Tuist をインストールするためにワークフローに追加のステップを加えられます。

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
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を作成し、`TUIST_TOKEN` という名前のシークレット環境変数として追加します。

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io) では、組み込みの [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) および [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) ワークフローステップを使用するか、**Git Clone** ステップの後に **Custom Script** ステップを追加して自身で Tuist をインストールできます。

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
> Tuist Install ステップは Homebrew で Tuist をインストールし、`tuist generate` を実行します。バージョンを固定するには **Tuist Version** 入力を設定し、その後 Tuist Commands ステップを追加して `tuist test` や `tuist build` などのコマンドを実行します。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> を作成し、[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables) に `TUIST_TOKEN` という名前の変数として追加し、ビルド構成でそのグループを選択します。ロックアイコンを使用して変数をシークレットとしてマークします。

## 実行レポート {#run-report}

Tuist が実行をアップロードすると、そのダッシュボード URL がログに出力されます。ログをスクレイピングせずに URL を取得するため（例：ジョブが失敗した際にテストレポートのリンクを Slack に投稿する場合や、実行を独自のツールに取り込む場合）、`tuist test`、`tuist xcodebuild test`、または `tuist xcodebuild build` に `--run-report-path` を渡すか（あるいは `TUIST_RUN_REPORT_PATH` を設定します）。Tuist は実行のアップロード完了後、そのパスに JSON レポートを書き込みます。

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
| `runId` | string | 実行の一意な識別子。 |
| `status` | string | `"success"` または `"failure"`。 |
| `runURL` | string | 実行のダッシュボード URL。常に存在します。 |
| `testRunURL` | string? | テスト実行のダッシュボード URL。コマンドがテストを実行した場合に存在します。 |
| `buildRunURL` | string? | ビルド実行のダッシュボード URL。コマンドがビルドを実行した場合に存在します。 |
| `testRuns` | array | スキーマごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および `skippedTestModules`。テスト数はテストケースの数であり、`skippedTests` は結果バンドルでスキップされたと報告された数を示します。`skippedTestModules` は <.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link> によってスキップされたテストモジュールの数を示し、選択的テストが適用されない場合や実行がテストシャードの場合は省略されます。 |
| `buildRuns` | array | スキーマごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL` と `buildRunURL` は独立しています。ビルドとテストの両方を実行するコマンドは両方の URL を出力しますが、ログでは実行ごとに 1 つの URL しか出力できません。

> [!NOTE]
> **レポートの書き込みタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CI では自動的に行われます。パスは各実行の開始時にクリアされるため、レポートを生成しない実行では以前の古いレポートが残るのではなく、何も残りません。

GitLab CI では、後続のジョブに URL を公開するためによく使われる方法として、[`dotenv` レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) を使用します：

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
