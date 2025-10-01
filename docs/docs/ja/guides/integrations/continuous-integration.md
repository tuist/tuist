---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 継続的インテグレーション（CI）{#continuous-integration-ci}。

Tuistは[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)環境で使うことができる。以下のセクションでは、さまざまなCIプラットフォームでこれを行う方法の例を示します。

## 例 {#examples}

CIワークフローでTuistコマンドを実行するには、CI環境にインストールする必要がある。

### Xcodeクラウド {#xcode-cloud}

Xcodeプロジェクトを真実のソースとして使用する[Xcode
Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールし、必要なコマンドを実行するために[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります、例えば`tuist
generate` ：

::コードグループ

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
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
:::
### コードマジック {#codemagic}

Codemagic](https://codemagic.io)では、Tuistをインストールするワークフローに追加のステップを加えることができる：

コードグループ
```yaml [Mise]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist build
```
```yaml [Homebrew]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist build
```
:::

### GitHubアクション {#github-actions}

GitHub
Actions](https://docs.github.com/en/actions)では、Tuistをインストールする追加のステップを追加することができ、Miseのインストールを管理する場合には、MiseとTuistのインストールを抽象化する[mise-action](https://github.com/jdx/mise-action)を使用することができます：

コードグループ
```yaml [Mise]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jdx/mise-action@v2
      - run: tuist build
```
```yaml [Homebrew]
name: test
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  lint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: brew install --formula tuist@x.y.z
      - run: tuist build
```
:::

::: tip 環境間でTuistのバージョンを固定するために、`mise use --pin`
をTuistプロジェクトで使用することをお勧めします。このコマンドはTuistのバージョンを含む`.tool-versions` ファイルを作成する：

## 認証 {#authentication}

1}cache</LocalizedLink>のようなサーバーサイドの機能を使う場合、CIワークフローからサーバーへのリクエストを認証する方法が必要になります。そのためには、以下のコマンドを実行することで、プロジェクトスコープのトークンを生成することができる：

```bash
tuist project tokens create my-handle/MyApp
```

このコマンドは、`my-account/my-project`
というフルハンドルのプロジェクト用のトークンを生成します。この値をCI環境の環境変数`TUIST_CONFIG_TOKEN`
に設定し、公開されないようにシークレットに設定する。

> [重要] CI環境の検出 TuistはCI環境で動作していることを検出したときのみトークンを使用します。CI環境が検出されない場合は、環境変数`CI`
> を`1` に設定することで、トークンを強制的に使用することができます。
