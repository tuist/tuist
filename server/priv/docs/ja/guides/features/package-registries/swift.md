---
{
  "title": "Swift",
  "titleTemplate": ":title · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuistのグローバルキャッシュネットワークを活用したSwiftパッケージレジストリにより、Swift Package Managerの依存関係解決を数分から数秒に短縮します。"
}
---
# Swift Package Registry {#swift-package-registry}

依存関係の数が増えると、その解決にかかる時間も増大します。[CocoaPods](https://cocoapods.org/)や[npm](https://www.npmjs.com/)などの他のパッケージマネージャーは中央集権型ですが、Swift Package Managerはそうではありません。そのため、SwiftPMは各リポジトリのディープクローンを実行して依存関係を解決する必要があり、時間がかかり、中央集権型のアプローチよりも多くのメモリを消費します。この問題に対処するため、Tuistは[Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)の実装を提供しており、_実際に必要_ なコミットのみをダウンロードできます。レジストリ内のパッケージは[Swift Package Index](https://swiftpackageindex.com/)に基づいています。そこでパッケージが見つかる場合、そのパッケージはTuist Registryでも利用可能です。さらに、パッケージはエッジストレージを使用して世界中に分散されており、解決時のレイテンシを最小限に抑えます。

## 使用方法 {#usage}

レジストリのセットアップには2つの方法があります。

### オプション1: 生成時の自動セットアップ（推奨） {#automatic-setup}

Tuistを使用してプロジェクトを生成している場合、`Tuist.swift`構成で`registryEnabled`オプションを設定することでレジストリを有効にできます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

このオプションを使用すると、`tuist generate`によってワークスペース内にレジストリ構成ファイルが自動的に作成されます。これにより、`tuist registry setup`を個別に実行する必要がなくなります。

> [!TIP]
> `registryEnabled`は、TuistのXcodeProjベースの統合ではなく、XcodeのデフォルトのSwift Package Manager統合を通じて依存関係を統合するプロジェクトに対してもレジストリを構成します。ただし、ソースコントロールURLで宣言されたパッケージをレジストリから解決するようにXcodeを構成するわけではありません。そのためには、各マシンで一度`tuist registry setup`を実行してください。詳細は<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソースコントロールパッケージの解決</.localized_link>をご覧ください。


### オプション2: 手動セットアップ {#manual-setup}

レジストリを手動でセットアップするには、プロジェクトのディレクトリで次のコマンドを実行します。

```bash
tuist registry setup
```

このコマンドは、プロジェクトでレジストリを有効にするレジストリ構成ファイルを生成します。チーム全体がレジストリの恩恵を受けられるよう、このファイルをコミットしてください。

### 認証（任意） {#authentication}

認証は**任意**です。認証なしでも、IPアドレスあたり**毎分1,000リクエスト**のレート制限でレジストリを利用できます。**毎分20,000リクエスト**というより高いレート制限を得るには、以下を実行して認証を行います。

```bash
tuist registry login
```

> [!NOTE]
> 認証には<.localized_link href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</.localized_link>が必要です。


### 依存関係の解決 {#resolving-dependencies}

ソースコントロールではなくレジストリから依存関係を解決するには、プロジェクトのセットアップに応じて以下のガイドをご覧ください。
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI上でレジストリをセットアップするには、このガイドに従ってください：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">継続的インテグレーション</.localized_link>。

### パッケージレジストリ識別子 {#package-registry-identifiers}

`Package.swift`または`Project.swift`ファイルでパッケージレジストリ識別子を使用する場合、パッケージのURLをレジストリの規約に変換する必要があります。レジストリ識別子は常に`{organization}.{repository}`の形式になります。例えば、`https://github.com/pointfreeco/swift-composable-architecture`パッケージのレジストリを使用する場合、パッケージレジストリ識別子は`pointfreeco.swift-composable-architecture`となります。

> [!NOTE]
> 識別子にはドットを2つ以上含めることはできません。リポジトリ名にドットが含まれている場合は、アンダースコアに置き換えられます。例えば、`https://github.com/groue/GRDB.swift`パッケージのレジストリ識別子は`groue.GRDB_swift`となります。
