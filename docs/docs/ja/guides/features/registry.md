---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# レジストリ {#registry}

> [重要】要件
> - A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>

依存関係の数が増えると、それらを解決する時間も増えます。CocoaPods](https://cocoapods.org/)や[npm](https://www.npmjs.com/)のような他のパッケージマネージャは集中管理されていますが、Swift
Package Managerはそうではありません。そのため、SwiftPM
は各リポジトリのディープクローンを行うことで依存関係を解決する必要があり、集中型のアプローチよりも時間がかかり、より多くのメモリを消費します。これに対処するために、Tuistは[Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)の実装を提供し、_実際に必要なコミットだけをダウンロードできるようにしています_
。レジストリ内のパッケージは[Swift Package Index](https://swiftpackageindex.com/)に基づいています。-
もしそこでパッケージを見つけることができれば、そのパッケージはTuistレジストリでも利用可能です。さらに、パッケージは、それらを解決する際の待ち時間を最小にするために、エッジストレージを使用して世界中に分散されています。

## 使用法 {#usage}

レジストリを設定してログインするには、プロジェクトのディレクトリで以下のコマンドを実行する：

```bash
tuist registry setup
```

このコマンドはレジストリ設定ファイルを生成し、レジストリにログインする。チームの他のメンバーがレジストリにアクセスできるようにするには、生成されたファイルがコミットされていることを確認し、チームのメンバーが以下のコマンドを実行してログインするようにしてください：

```bash
tuist registry login
```

これでレジストリにアクセスできるようになった！ソース管理からではなくレジストリから依存関係を解決するには、プロジェクトの設定に基づいて読み進めてください：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  project</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Xcode
  パッケージ統合で生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">XcodeProj
  ベースのパッケージ統合で生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift
  パッケージ</LocalizedLink>

CI上でレジストリを設定するには、このガイドに従ってください：<LocalizedLink href="/guides/features/registry/continuous-integration">継続的インテグレーション</LocalizedLink>.

### パッケージ・レジストリ識別子 {#package-registry-identifiers}.

`Package.swift` または`Project.swift` ファイルでパッケージのレジストリ識別子を使用する場合は、パッケージの URL
をレジストリの規約に変換する必要があります。レジストリ識別子は常に`{organization}.{repository}`
の形式です。たとえば、`https://github.com/pointfreeco/swift-composable-architecture`
パッケージのレジストリを使用する場合、パッケージのレジストリ識別子は`pointfreeco.swift-composable-architecture`
となります。

> [注意]
> 識別子にドットを複数含めることはできません。リポジトリ名にドットが含まれる場合、アンダースコアに置き換えられます。例えば、`https://github.com/groue/GRDB.swift`
> パッケージはレジストリ識別子`groue.GRDB_swift` を持ちます。
