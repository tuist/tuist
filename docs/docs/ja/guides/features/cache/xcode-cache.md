---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcodeキャッシュ {#xcode-cache}

TuistはXcodeのコンパイルキャッシュに対応しており、ビルドシステムのキャッシュ機能を活用することで、チーム間でコンパイル成果物を共有することができます。

## 設定{#setup}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
- Xcode 26.0 以降
<!-- -->
:::

まだTuistのアカウントやプロジェクトをお持ちでない場合は、以下のコマンドを実行して作成できます：

```bash
tuist init
```

`の fullHandle` を参照する`Tuist.swift`
ファイルを作成したら、以下のコマンドを実行してプロジェクトのキャッシュ設定を行うことができます:

```bash
tuist setup cache
```

このコマンドは、Swiftの[ビルドシステム](https://github.com/swiftlang/swift-build)がコンパイル結果の共有に使用するローカルキャッシュサービスを起動時に実行するための[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)を作成します。このコマンドは、ローカル環境とCI環境の両方で一度ずつ実行する必要があります。

CI上でキャッシュを設定するには、<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認してください。

### Xcodeのビルド設定を構成する{#configure-xcode-build-settings}

Xcodeプロジェクトに以下のビルド設定を追加してください：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`、COMPILATION_CACHE_REMOTE_SERVICE_PATH、`
、および`、COMPILATION_CACHE_ENABLE_PLUGIN、`
は、Xcodeのビルド設定UIには直接表示されないため、**のユーザー定義ビルド設定** として追加する必要があります。

::: info SOCKET PATH
<!-- -->
`tuist setup cache`
を実行すると、ソケットパスが表示されます。これは、プロジェクトのフルハンドルからスラッシュをアンダースコアに置き換えたものです。
<!-- -->
:::

`xcodebuild` を実行する際、次のようなフラグを追加することで、これらの設定を指定することもできます。

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
プロジェクトがTuistによって生成されている場合、手動で設定を行う必要はありません。

その場合は、`Tuist.swift` ファイルに、`enableCaching: true` を追加するだけで済みます：
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

CI環境でキャッシュを有効にするには、ローカル環境と同じコマンドを実行する必要があります：`tuist setup cache` 。

認証には、<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>（対応しているCIプロバイダーの場合、推奨）または、`環境変数TUIST_TOKEN`
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

トークンベースの認証や、Xcode Cloud、CircleCI、Bitrise、Codemagic などの他の CI
プラットフォームに関する例については、<LocalizedLink href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</LocalizedLink>を参照してください。
