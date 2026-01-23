---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcodeキャッシュ {#xcode-cache}

TuistはXcodeコンパイルキャッシュのサポートを提供し、ビルドシステムのキャッシュ機能を活用することでチーム間でコンパイル成果物を共有できるようにします。

## 設定{#setup}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
- Xcode 26.0以降
<!-- -->
:::

Tuistアカウントとプロジェクトをお持ちでない場合は、以下を実行して作成できます：

```bash
tuist init
```

`Tuist.swift ファイルが用意できたら、` ファイルで`fullHandle`
を参照するように設定し、以下のコマンドを実行してプロジェクトのキャッシュを設定できます：

```bash
tuist setup cache
```

このコマンドは、起動時にローカルキャッシュサービスを実行する[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)を作成します。このサービスはSwiftの[ビルドシステム](https://github.com/swiftlang/swift-build)がコンパイル成果物を共有するために使用します。このコマンドは、ローカル環境とCI環境の両方で一度実行する必要があります。

CI上でキャッシュを設定するには、<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認してください。

### Xcodeのビルド設定を構成する{#configure-xcode-build-settings}

Xcodeプロジェクトに以下のビルド設定を追加してください：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH` および`COMPILATION_CACHE_ENABLE_PLUGIN`
は、Xcodeのビルド設定UIに直接表示されないため、**のユーザー定義ビルド設定** として追加する必要があります。

::: info SOCKET PATH
<!-- -->
`tuist setup cache`
を実行するとソケットパスが表示されます。これはプロジェクトのフルハンドルをスラッシュからアンダースコアに置換したものです。
<!-- -->
:::

`の実行時に以下のフラグを追加することで、これらの設定を指定することもできます。例：`xcodebuild` `

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
プロジェクトがTuistで生成されている場合、設定を手動で設定する必要はありません。

`その場合、必要なのは以下のコードを Tuist.swift ファイルに追加することだけです:`` enableCaching: true`
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### 継続的インテグレーション #{continuous-integration}

CI環境でキャッシュを有効化するには、ローカル環境と同様のコマンドを実行する必要があります：`tuist setup cache`

認証には、<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>（対応するCIプロバイダーに推奨）または、`のTUIST_TOKEN環境変数`
経由の<LocalizedLink href="/guides/server/authentication#account-tokens">アカウントトークン</LocalizedLink>のいずれかを使用できます。

OIDC認証を使用したGitHub Actionsのワークフロー例：
```yaml
name: Build

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
      - # Your build steps
```

トークンベース認証やXcode
Cloud、CircleCI、Bitrise、Codemagicなどの他のCIプラットフォームを含む、より多くの例については<LocalizedLink href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</LocalizedLink>を参照してください。
