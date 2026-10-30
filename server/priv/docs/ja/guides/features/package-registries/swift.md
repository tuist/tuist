---
{
  "title": "Swift",
  "titleTemplate": ":title · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuistのグローバルキャッシュネットワークを活用したTuist Swiftパッケージレジストリにより、Swift Package Managerの依存関係解決を数分から数秒に短縮します。"
}
---
# Swift Package Registry {#swift-package-registry}

依存関係の数が増えると、それらの解決にかかる時間も増大します。[CocoaPods](https://cocoapods.org/) や [npm](https://www.npmjs.com/) などの他のパッケージマネージャーは中央集権型ですが、Swift Package Manager はそうではありません。そのため、SwiftPM は各リポジトリをディープクローンして依存関係を解決する必要があり、時間がかかり、中央集権型のアプローチよりも多くのメモリを消費します。この問題に対処するため、Tuist は [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) の実装を提供しており、_実際に必要な_ コミットだけをダウンロードできます。レジストリ内のパッケージは [Swift Package Index](https://swiftpackageindex.com/) に基づいています。そこにパッケージがあれば、Tuist Registry でも利用可能です。さらに、パッケージはエッジストレージを使用して世界中に分散されており、解決時のレイテンシを最小限に抑えています。

## 使い方 {#usage}

レジストリを設定する方法は2つあります。

### オプション1: 生成時の自動設定（推奨） {#automatic-setup}

Tuist を使用してプロジェクトを生成している場合、`Tuist.swift` 構成で `registryEnabled` オプションを設定することでレジストリを有効にできます。

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

このオプションを使用すると、`tuist generate` がワークスペース内にレジストリ構成ファイルを自動的に作成します。これにより、`tuist registry setup` を個別に実行する必要がなくなります。

> [!TIP]
> `registryEnabled` は、Tuist の XcodeProj ベースの統合ではなく、Xcode のデフォルトの Swift Package Manager 統合を通じて依存関係を統合するプロジェクトに対してもレジストリを構成します。ただし、レジストリからソースコントロール URL で宣言されたパッケージを解決するように Xcode を構成するわけではありません。そのためには、各マシンで `tuist registry setup` を一度実行してください。詳細は <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Resolving source control packages</.localized_link> を参照してください。


### オプション2: 手動設定 {#manual-setup}

レジストリを手動で設定するには、プロジェクトのディレクトリで次のコマンドを実行します。

```bash
tuist registry setup
```

このコマンドは、プロジェクトでレジストリを有効にするレジストリ構成ファイルを生成します。チーム全体がレジストリの恩恵を受けられるよう、このファイルをコミットしてください。

### 認証（任意） {#authentication}

認証は **任意** です。認証なしでも、IP アドレスあたり **1分間に1,000リクエスト** のレート制限付きでレジストリを利用できます。**1分間に20,000リクエスト** のより高いレート制限を得るには、次のコマンドを実行して認証してください。

```bash
tuist registry login
```

> [!NOTE]
> 認証には <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link> が必要です。


### 依存関係の解決 {#resolving-dependencies}

ソースコントロールではなくレジストリから依存関係を解決するには、プロジェクトの設定に応じて以下のガイドをご覧ください。
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI でレジストリを設定するには、次のガイドに従ってください。<.localized_link href="/guides/features/package-registries/swift/continuous-integration">Continuous integration</.localized_link>。

### パッケージレジストリの識別子 {#package-registry-identifiers}

`Package.swift` または `Project.swift` ファイルでパッケージレジストリの識別子を使用する場合、パッケージの URL をレジストリの規則に変換する必要があります。レジストリの識別子は常に `{organization}.{repository}` の形式です。例えば、`https://github.com/pointfreeco/swift-composable-architecture` パッケージのレジストリを使用する場合、パッケージレジストリの識別子は `pointfreeco.swift-composable-architecture` になります。

> [!NOTE]
> 識別子にはドットを2つ以上含めることはできません。リポジトリ名にドットが含まれている場合は、アンダースコアに置き換えられます。例えば、`https://github.com/groue/GRDB.swift` パッケージのレジストリ識別子は `groue.GRDB_swift` になります。
