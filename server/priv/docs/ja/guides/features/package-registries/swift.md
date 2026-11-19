---
{
  "title": "Swift",
  "titleTemplate": ":title · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuistのグローバルキャッシュネットワークを活用したSwiftパッケージレジストリで、Swift Package Managerの依存関係解決を数分から数秒に短縮します。"
}
---
# Swift Package Registry {#swift-package-registry}

依存関係の数が増えると、それらの解決にかかる時間も増えます。[CocoaPods](https://cocoapods.org/) や [npm](https://www.npmjs.com/) などの他のパッケージマネージャーは中央集権型ですが、Swift Package Manager はそうではありません。そのため、SwiftPM は各リポジトリをディープクローンして依存関係を解決する必要があり、時間がかかり、中央集権型のアプローチよりも多くのメモリを消費します。この問題に対処するため、Tuist は [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) の実装を提供しており、_実際に必要_ なコミットのみをダウンロードできます。レジストリ内のパッケージは [Swift Package Index](https://swiftpackageindex.com/) に基づいています。そこでパッケージが見つかる場合、そのパッケージは Tuist Registry でも利用可能です。さらに、パッケージはエッジストレージを使用して世界中に分散されており、解決時のレイテンシを最小限に抑えています。

## 使用方法 {#usage}

レジストリの設定方法には次の 2 つがあります。

### オプション 1: 生成時の自動セットアップ（推奨） {#automatic-setup}

Tuist を使用してプロジェクトを生成している場合は、`Tuist.swift` 構成で `registryEnabled` オプションを設定することでレジストリを有効にできます。

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

このオプションを使用すると、`tuist generate` がワークスペースにレジストリ構成ファイルを自動的に作成します。これにより、`tuist registry setup` を個別に実行する必要がなくなります。

> [!TIP]
> `registryEnabled` は、Tuist の XcodeProj ベースの統合ではなく、Xcode のデフォルトの Swift Package Manager 統合を通じて依存関係を統合するプロジェクトに対してもレジストリを構成します。ソース管理 URL で宣言されたパッケージをレジストリから解決するように Xcode を構成するものではありません。そのためには、<.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">ソース管理パッケージの解決</.localized_link> で説明されているように、各マシンで `tuist registry setup` を一度実行してください。


### オプション 2: 手動セットアップ {#manual-setup}

レジストリを手動で設定するには、プロジェクトのディレクトリで次のコマンドを実行します。

```bash
tuist registry setup
```

このコマンドは、プロジェクトでレジストリを有効にするレジストリ構成ファイルを生成します。チームもレジストリの恩恵を受けられるよう、このファイルをコミットしてください。

### 認証（任意） {#authentication}

認証は **任意** です。認証なしでも、IP アドレスあたり **毎分 1,000 リクエスト** のレート制限でレジストリを利用できます。**毎分 20,000 リクエスト** のより高いレート制限を得るには、次のコマンドを実行して認証します。

```bash
tuist registry login
```

> [!NOTE]
> 認証には <.localized_link href="/guides/server/accounts-and-projects">Tuist アカウントとプロジェクト</.localized_link> が必要です。


### 依存関係の解決 {#resolving-dependencies}

ソース管理ではなくレジストリから依存関係を解決するには、プロジェクトの設定に応じて以下の情報を参照してください。
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI でレジストリを設定するには、次のガイドに従ってください。<.localized_link href="/guides/features/package-registries/swift/continuous-integration">継続的インテグレーション</.localized_link>

### パッケージレジストリ識別子 {#package-registry-identifiers}

`Package.swift` または `Project.swift` ファイルでパッケージレジストリ識別子を使用する場合、パッケージの URL をレジストリの規則に変換する必要があります。レジストリ識別子は常に `{organization}.{repository}` の形式です。たとえば、`https://github.com/pointfreeco/swift-composable-architecture` パッケージのレジストリを使用する場合、パッケージレジストリ識別子は `pointfreeco.swift-composable-architecture` になります。

> [!NOTE]
> 識別子にはドットを 1 つしか含めることができません。リポジトリ名にドットが含まれている場合は、アンダースコアに置き換えられます。たとえば、`https://github.com/groue/GRDB.swift` パッケージのレジストリ識別子は `groue.GRDB_swift` になります。
