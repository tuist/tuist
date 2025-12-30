---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# レジストリ {#registry}

依存関係の数が増えると、それらを解決する時間も増えます。CocoaPods](https://cocoapods.org/)や[npm](https://www.npmjs.com/)のような他のパッケージマネージャは集中管理されていますが、Swift
Package Managerはそうではありません。そのため、SwiftPM
は各リポジトリのディープクローンを行うことで依存関係を解決する必要があり、集中型のアプローチよりも時間がかかり、より多くのメモリを消費します。これに対処するために、Tuistは[Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)の実装を提供し、_実際に必要なコミットだけをダウンロードできるようにしています_
。レジストリ内のパッケージは[Swift Package Index](https://swiftpackageindex.com/)に基づいています。-
もしそこでパッケージを見つけることができれば、そのパッケージはTuistレジストリでも利用可能です。さらに、パッケージは、それらを解決する際の待ち時間を最小にするために、エッジストレージを使用して世界中に分散されています。

## 使用法 {#usage}

レジストリを設定するには、プロジェクトのディレクトリで以下のコマンドを実行する：

```bash
tuist registry setup
```

このコマンドは、あなたのプロジェクトでレジストリを有効にするレジストリ設定ファイルを生成します。あなたのチームもレジストリの恩恵を受けられるように、このファイルがコミットされていることを確認してください。

### 認証 （オプ シ ョ ナル） {#authentication} 認証。

認証は**オプションである** 。認証なしでは、IPアドレスごとに**1分あたり1,000リクエスト**
のレート制限でレジストリを使用できます。より高いレート制限**20,000リクエスト/分** を得るには、認証を実行してください：

```bash
tuist registry login
```

::: 情報
<!-- -->
認証には<LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>が必要です。
<!-- -->
:::

### 依存関係の解決{#resolving-dependencies}。

ソース・コントロールからではなくレジストリから依存関係を解決するには、プロジェクトのセットアップに基づいて読み進めてください：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode project</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Xcode パッケージ統合で生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">XcodeProj ベースのパッケージ統合で生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift パッケージ</LocalizedLink>

CI上でレジストリを設定するには、このガイドに従ってください：<LocalizedLink href="/guides/features/registry/continuous-integration">継続的インテグレーション</LocalizedLink>.

### パッケージ・レジストリ識別子 {#package-registry-identifiers}.

`Package.swift` または`Project.swift` ファイルでパッケージのレジストリ識別子を使用する場合は、パッケージの URL
をレジストリの規約に変換する必要があります。レジストリ識別子は常に`{organization}.{repository}`
の形式です。たとえば、`https://github.com/pointfreeco/swift-composable-architecture`
パッケージのレジストリを使用する場合、パッケージのレジストリ識別子は`pointfreeco.swift-composable-architecture`
となります。

::: 情報
<!-- -->
識別子には複数のドットを含めることはできません。リポジトリ名にドットが含まれる場合は、アンダースコアに置き換えられます。例えば、`https://github.com/groue/GRDB.swift`
パッケージは、レジストリ識別子`groue.GRDB_swift` を持つことになります。
<!-- -->
:::
