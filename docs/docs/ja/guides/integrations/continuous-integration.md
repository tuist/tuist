---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 継続的インテグレーション（CI）{#continuous-integration-ci}

継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration)ワークフローでTuistコマンドを実行するには、CI環境にインストールする必要がある。

認証はオプションだが、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>のようなサーバーサイドの機能を使いたい場合は必須である。

以下のセクションでは、異なるCIプラットフォームでこれを行う方法の例を示す。

## 例{#examples}

### GitHub アクション{#github-actions}

GitHub
Actions](https://docs.github.com/en/actions)では、<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を使うことで、秘密のない安全な認証ができます：

コードグループ
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

::: info OIDC SETUP
<!-- -->
OIDC認証を使用する前に、<LocalizedLink href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。OIDC
を動作させるには`permissions: id-token: write` が必要です。あるいは、`TUIST_TOKEN` secret を持つ
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> を使うこともできます。
<!-- -->
:::

::: チップ
<!-- -->
環境間でTuistのバージョンを固定するために、Tuistプロジェクトで`mise use --pin`
を使用することを推奨する。このコマンドはTuistのバージョンを含む`.tool-versions` ファイルを作成する。
<!-- -->
:::

### Xcodeクラウド{#xcode-cloud}

Xcodeプロジェクトを真実のソースとして使用する[Xcode
Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールし、必要なコマンドを実行するために[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります、例えば`tuist
generate` ：

コードグループ

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

::: info AUTHENTICATION
<!-- -->
Xcode Cloud のワークフロー設定で`TUIST_TOKEN`
環境変数を設定し、<LocalizedLink href="/guides/server/authentication#project-tokens">プロジェクト・トークン</LocalizedLink>
を使用します。
<!-- -->
:::

### サークルCI{#circleci}

CircleCI](https://circleci.com)では、<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を使用して、セキュアでシークレットレスな認証を行うことができます：

コードグループ
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

::: info AUTHENTICATION
<!-- -->
OIDC認証を使用する前に、<LocalizedLink href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。CircleCI
OIDCトークンには接続したGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを認証します。あるいは、`TUIST_TOKEN`
環境変数で <LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> を使用することもできます。
<!-- -->
:::

### ビットライズ{#bitrise}

Bitrise](https://bitrise.io)では、<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を使用して、セキュアでシークレットレスな認証を行うことができます：

コードグループ
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

::: info AUTHENTICATION
<!-- -->
OIDC認証を使用する前に、<LocalizedLink href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。Bitrise
OIDCトークンには接続したGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを認証します。あるいは、`TUIST_TOKEN`
環境変数で <LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> を使用することもできます。
<!-- -->
:::

### コードマジック{#codemagic}

Codemagic](https://codemagic.io)では、Tuistをインストールするワークフローに追加のステップを加えることができる：

コードグループ
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

::: info AUTHENTICATION
<!-- -->
<LocalizedLink href="/guides/server/authentication#project-tokens">プロジェクト・トークン</LocalizedLink>を作成し、`TUIST_TOKEN` という秘密の環境変数として追加する。
<!-- -->
:::
