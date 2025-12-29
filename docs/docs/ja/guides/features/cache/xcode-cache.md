---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcodeキャッシュ {#xcode-cache}

TuistはXcodeコンパイルキャッシュのサポートを提供し、ビルドシステムのキャッシュ機能を活用することで、チームがコンパイル成果物を共有することを可能にする。

## セットアップ{#setup}

警告 要件
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
- Xcode 26.0以降
<!-- -->
:::

まだTuistのアカウントとプロジェクトを持っていない場合は、Tuistを起動してアカウントを作成することができる：

```bash
tuist init
```

`fullHandle` を参照する`Tuist.swift` ファイルを用意したら、これを実行することでプロジェクトのキャッシュを設定できる：

```bash
tuist setup cache
```

このコマンドは、Swift の [ビルドシステム](https://github.com/swiftlang/swift-build)
がコンパイルの成果物を共有するために使用する、起動時にローカルのキャッシュサービスを実行する
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
を作成します。このコマンドはローカルと CI 環境の両方で一度実行する必要があります。

CIでキャッシュを設定するには、<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証されている</LocalizedLink>ことを確認してください。

### Xcodeのビルド設定を構成する{#configure-xcode-build-settings}

Xcodeプロジェクトに以下のビルド設定を追加する：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH` と`COMPILATION_CACHE_ENABLE_PLUGIN`
は、Xcodeのビルド設定UIで直接公開されていないため、**ユーザー定義のビルド設定** として追加する必要があることに注意してください：

::: info SOCKET PATH
<!-- -->
`tuist setup cache`
を実行すると、ソケットパスが表示されます。スラッシュをアンダースコアに置き換えたプロジェクトの完全なハンドルに基づいています。
<!-- -->
:::

これらの設定は、`xcodebuild` を実行する際に、以下のようなフラグを追加して指定することもできる：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
プロジェクトがTuistによって生成されている場合は、手動で設定する必要はない。

その場合、`Tuist.swift` ファイルに`enableCaching: true` を追加するだけでよい：
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

### 継続的インテグレーション#{continuous-integration}。

CI環境でキャッシュを有効にするには、ローカル環境と同じコマンドを実行する必要がある：`tuist setup cache`.

さらに、`TUIST_TOKEN`
環境変数が設定されていることを確認する必要があります。こちらのドキュメント<LocalizedLink href="/guides/server/authentication#as-a-project"></LocalizedLink>に従って作成できます。`TUIST_TOKEN`
環境変数__ がビルドステップに存在する必要がありますが、CIワークフロー全体に設定することをお勧めします。

GitHub Actions のワークフローの例は次のようになります：
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
