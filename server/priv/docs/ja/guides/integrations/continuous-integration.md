---
{
  "title": "継続的インテグレーション（CI）",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "CIワークフローでTuistを使用する方法を学びます。"
}
---
# 継続的インテグレーション (CI) {#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration) ワークフローで Tuist コマンドを実行するには、CI 環境に Tuist をインストールする必要があります。 

認証は任意ですが、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>などのサーバーサイド機能を使用する場合は必須です。Tuist のインストール後に CI 実行を短縮しコストを削減するには、[ビルドの低速化](https://tuist.dev/solutions/slow-builds)と[CI コスト](https://tuist.dev/solutions/ci-costs)をご覧ください。

以下のセクションでは、さまざまな CI プラットフォームでの実施例を示します。Struo は独自のネイティブな Tuist プロバイダーを通じて接続するため、Tuist CLI は不要です。そのワークフローについては[Struo](#struo)をご覧ください。

## Struo {#struo}

<a id="once"></a>

<.localized_link href="/guides/get-started/struo-project">Struo を使い始める</.localized_link>からプロバイダーとキャッシュバインディングをコミットしてください。[Struo のインストール手順](https://struo.run/docs/guide/getting-started)に従ってジョブ内に Struo をインストールし、キャッシュ可能な作業を実行する前に認証を行います。

GitHub Actions、CircleCI、および Bitrise は Struo のヘッドレス OpenID Connect ログインをサポートしています。<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link>の説明に従って、リポジトリを Tuist プロジェクトに接続してください。GitHub Actions では、identity-token 権限を付与します。

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
      # Pin Struo in your repository's mise.toml.
      - run: struo auth login --provider tuist --no-browser
      - run: struo build MyTarget
      - run: struo test
```

ターゲットが必要とするツールチェーンを備えた OS を選択してください。`MyTarget`を自分のターゲットに置き換え、既存のツールインストールワークフローを通じて Struo のバージョンを固定します。生成されたセッションは、ジョブ中のキャッシュアクセス、レポート作成、およびアーティファクト公開のために再利用されます。

他のプロバイダーでは、`TUIST_TOKEN`に必要な操作が許可された<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を設定してください。これを CI のシークレットストアに保存し、`struo.toml`やワークフローのソースコードには決して保存しないでください。そのトークンを使用する場合、インタラクティブなログイン手順は不要です。

マルチワーカー構成の場合は、<.localized_link href="/guides/features/test-sharding/struo">Struo テストシャーディング</.localized_link>に従ってください。アプリケーションを公開するには、明示的な<.localized_link href="/guides/features/previews/struo">Struo プレビュー公開</.localized_link>ステップを追加します。通常のビルドではプレビューは暗黙的に公開されません。

## 例 {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link>を使用して安全でシークレット不要の認証を行えます。

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
> **OIDC 設定**
>
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを接続</.localized_link>して Tuist プロジェクトに関連付ける必要があります。OIDC が動作するには`permissions: id-token: write`が必要です。Tuist 4.218.0 以降では、CLI が初回リクエスト時に ID トークンを交換するため、ワークフローに`tuist auth login`ステップは不要です。それより前のバージョンでは、他の Tuist コマンドの前に`tuist auth login`を実行してください。あるいは、`TUIST_TOKEN`シークレットと共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


> [!TIP]
> Tuist プロジェクトで`mise use --pin`を使用して、環境間で Tuist のバージョンを固定することを推奨します。このコマンドは`mise.toml`ファイル内の Tuist バージョンを固定します。


### Xcode Cloud {#xcode-cloud}

Xcode プロジェクトを信頼できる情報源として使用する[Xcode Cloud](https://developer.apple.com/xcode-cloud/)では、Tuist をインストールし必要なコマンド（例：`tuist generate`）を実行するために、[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります。

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
> Xcode Cloud ワークフロー設定で`TUIST_TOKEN`環境変数を設定することで、<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用してください。


### CircleCI {#circleci}

[CircleCI](https://circleci.com)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link>を使用して安全でシークレット不要の認証を行えます。

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
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを接続</.localized_link>して Tuist プロジェクトに関連付ける必要があります。CircleCI OIDC トークンには接続済みの GitHub リポジトリが含まれており、Tuist はこれを使用してプロジェクトへのアクセスを承認します。Tuist 4.218.0 以降では、CLI が初回リクエスト時に ID トークンを交換するため、`tuist auth login`ステップは不要です。それより前のバージョンでは、他の Tuist コマンドの前に`mise exec -- tuist auth login`を実行してください。あるいは、`TUIST_TOKEN`環境変数と共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)では、<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認証</.localized_link>を使用して安全でシークレット不要の認証を行えます。

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
> OIDC 認証を使用する前に、<.localized_link href="/guides/integrations/gitforge/github">GitHub リポジトリを接続</.localized_link>して Tuist プロジェクトに関連付ける必要があります。Bitrise OIDC トークンには接続済みの GitHub リポジトリが含まれており、Tuist はこれを使用してプロジェクトへのアクセスを承認します。Tuist 4.218.0 以降では、CLI が初回リクエスト時に ID トークンを交換するため、`tuist auth login`ステップは不要です。それより前のバージョンでは、他の Tuist コマンドの前に`mise exec -- tuist auth login`を実行してください。あるいは、`TUIST_TOKEN`環境変数と共に<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を使用することもできます。


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)では、Tuist をインストールするためにワークフローに追加のステップを加えることができます。

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
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、`TUIST_TOKEN`という名前のシークレット環境変数として追加してください。

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)では、組み込みの[Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install)および[Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands)ワークフローステップを使用するか、**Git Clone**ステップの後に**Custom Script**ステップを追加して自分で Tuist をインストールできます。

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
> Tuist Install ステップは Homebrew で Tuist をインストールし、`tuist generate`を実行します。**Tuist Version** 入力にバージョンを指定して固定し、その後 Tuist Commands ステップを追加して`tuist test`や`tuist build`などのコマンドを実行してください。

> [!NOTE]
> **認証**
>
> <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>を作成し、[環境変数グループ](https://docs.appcircle.io/build/build-environment-variables)内に`TUIST_TOKEN`という名前の変数として追加して、ビルド構成でそのグループを選択してください。変数は鍵アイコンを使ってシークレットとしてマークしてください。

## xcodebuild の出力フォーマット {#xcodebuild-output-formatting}

`tuist build`、`tuist test`、`tuist xcodebuild build`、および`tuist xcodebuild test`は、[xcbeautify](https://github.com/cpisciotta/xcbeautify) のフォーマッタを使用して`xcodebuild`の出力を整形するため、これらのコマンドを自分で xcbeautify にパイプする必要はありません。GitHub Actions では、`GITHUB_ACTIONS`環境変数によって検出され、Tuist は xcbeautify の GitHub Actions レンダラーを使用します。これにより、コンパイラの警告、エラー、テストの失敗が実行サマリーとプルリクエスト内のアノテーションとして表示されます。それ以外の場所ではターミナルレンダラーを使用し、出力がパイプされていない場合や`NO_COLOR`が設定されていない場合は色付けされます。

明確なエラーなしでビルドが失敗した場合など、`xcodebuild`の未整形出力を表示するには`--verbose`を渡してください。

ジョブが Tuist を介さずに直接`xcodebuild`を呼び出す場合は、自分で xcbeautify にパイプし、ビルドが失敗してもステップが失敗するように`pipefail`を設定してください。

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## 実行レポート {#run-report}

Tuist が実行をアップロードすると、そのダッシュボード URL がログに出力されます。ログをスクレイピングせずにこれらを取得するには（たとえば、ジョブが失敗したときにテストレポートのリンクを Slack に投稿したり、独自ツールに実行データを取り込んだりする場合）、`tuist test`、`tuist xcodebuild test`、または`tuist xcodebuild build`に`--run-report-path`を渡すか（あるいは`TUIST_RUN_REPORT_PATH`を設定してください）。Tuist は実行がアップロードされると、そのパスに JSON レポートを書き込みます。

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
| `runURL` | 文字列 | 実行のダッシュボード URL。常に存在します。 |
| `testRunURL` | 文字列? | テスト実行のダッシュボード URL。コマンドがテストを実行した場合に存在します。 |
| `buildRunURL` | 文字列? | ビルド実行のダッシュボード URL。コマンドがビルドを実行した場合に存在します。 |
| `testRuns` | 配列 | スキーマごとのテスト結果：`scheme`、`succeeded`、`totalTests`、`skippedTests`、`ranTests`、`failedTestNames`、`ranTestModules`、および`skippedTestModules`。テストカウントはテストケースの数であり、`skippedTests`は結果バンドルでスキップされたもの数を示します。`skippedTestModules`は<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>によってスキップされたテストモジュールの数を示し、選択的テストが適用されなかった場合や実行がテストシャードの場合は省略されます。 |
| `buildRuns` | 配列 | スキーマごとのビルド結果：`scheme`、`succeeded`、`durationInSeconds`。 |

`testRunURL`と`buildRunURL`は独立しています。ビルドとテストの両方を実行するコマンドは両方の URL を書き込みますが、ログではそれができません。ログは実行ごとに 1 つの URL しか出力しません。

> [!NOTE]
> **レポートが書き込まれるタイミング**
>
> レポートはサーバーにアップロードされた実行に対してのみ書き込まれます。これには認証が必要で、CI では自動的に行われます。パスは各実行の開始時にクリアされるため、レポートを生成しない実行でも以前の古いレポートが残ることはありません。

GitLab CI では、後続のジョブに URL を公開するために[`dotenv`レポート](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)を使用するのが一般的です。

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
