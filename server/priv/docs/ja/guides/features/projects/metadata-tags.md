---
{
  "title": "メタデータタグ",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "ターゲットのメタデータタグを使用して、プロジェクトの特定の部分を整理し、重点的に管理する方法を学びます"
}
---
# メタデータタグ {#metadata-tags}

プロジェクトの規模と複雑さが増すにつれて、コードベース全体を一度に扱うのは非効率になりがちです。Tuist は**メタデータタグ**を提供し、ターゲットを論理的なグループに整理したり、開発中にプロジェクトの特定の部分に集中したりできるようにします。

## メタデータタグとは？ {#what-are-metadata-tags}

メタデータタグは、プロジェクト内のターゲットに付与できる文字列ラベルです。これらはマーカーとして機能し、次のことを可能にします。

- **関連するターゲットをグループ化** - 同じ機能、チーム、またはアーキテクチャ層に属するターゲットにタグを付ける
- **ワークスペースを絞り込む** - 特定のタグを持つターゲットのみを含むプロジェクトを生成する
- **ワークフローを最適化** - コードベースの無関係な部分を読み込まずに、特定の機能に取り組む
- **ソースとして保持するターゲットを選択** - キャッシュ時にソースとして保持したいターゲットのグループを選ぶ

タグはターゲットの `metadata` プロパティを使用して定義され、文字列の配列として保存されます。

## メタデータタグの定義 {#defining-metadata-tags}

プロジェクトのマニフェストにある任意のターゲットにタグを追加できます。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## タグ付きターゲットへの集中 {#focusing-on-tagged-targets}

ターゲットにタグを付けたら、`tuist generate` コマンドを使用して、特定のターゲットのみを含む焦点を絞ったプロジェクトを作成できます。

### タグで絞り込む

`tag:` プレフィックスを使用して、特定のタグに一致するすべてのターゲットを含むプロジェクトを生成します。

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 名前で絞り込む

名前を指定して特定のターゲットに焦点を当てることもできます。

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 絞込みの仕組み

ターゲットに焦点を当てると、次のようになります。

1. **含まれるターゲット** - クエリに一致するターゲットが生成されたプロジェクトに含まれます
2. **依存関係** - 焦点を当てたターゲットのすべての依存関係が自動的に含まれます
3. **テストターゲット** - 焦点を当てたターゲットのテストターゲットが含まれます
4. **除外** - その他のすべてのターゲットはワークスペースから除外されます

つまり、機能の開発に必要なものだけを含む、より小さく管理しやすいワークスペースが得られます。

## タグの命名規則 {#tag-naming-conventions}

タグには任意の文字列を使用できますが、一貫した命名規則に従うことでタグを整理しやすくなります。

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

`feature:`、`team:`、`layer:` などのプレフィックスを使用すると、各タグの目的を理解しやすく、命名の衝突を避けられます。

## システムタグ {#system-tags}

Tuist はシステム管理のタグに `tuist:` プレフィックスを使用します。これらのタグは Tuist によって自動的に適用され、キャッシュプロファイルで使用して、生成されるコンテンツの特定のタイプを対象にできます。

### 利用可能なシステムタグ

| タグ | 説明 |
| --- | --- |
| `tuist:synthesized` | 静的ライブラリおよび静的フレームワークにおけるリソース処理のために Tuist が作成する合成バンドルターゲットに適用されます。これらのバンドルは、リソースアクセサ API を提供するために歴史的な理由で存在しています。 |

### キャッシュプロファイルでのシステムタグの使用

キャッシュプロファイルでシステムタグを使用して、合成ターゲットを含めたり除外したりできます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

> [!TIP]
> **合成バンドルは親ターゲットのタグを継承**
>
> 合成バンドルターゲットは、`tuist:synthesized` タグを受け取るだけでなく、親ターゲットのすべてのタグを継承します。つまり、静的ライブラリに `feature:auth` とタグ付けすると、その合成リソースバンドルには `feature:auth` と `tuist:synthesized` の両方のタグが付きます。


## プロジェクト記述ヘルパーでのタグの使用 {#using-tags-with-helpers}

<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link>を活用して、プロジェクト全体でのタグの適用方法を標準化できます。

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

その後、マニフェストで使用します。

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## メタデータタグの利点 {#benefits}

### 開発体験の向上

プロジェクトの特定の部分に焦点を当てることで、次のことが可能になります。

- **Xcode プロジェクトのサイズを削減** - 開くのが速く、ナビゲーションしやすい小さなプロジェクトで作業できます
- **ビルドを高速化** - 現在の作業に必要なものだけをビルドします
- **集中力を高める** - 無関係なコードによる気を散らす要素を避けます
- **インデックス作成を最適化** - Xcode がインデックスを作成するコード量が減り、オートコンプリートが高速になります

### プロジェクトの整理の改善

タグは、コードベースを整理するための柔軟な方法を提供します。

- **多次元での分類** - 機能、チーム、レイヤー、プラットフォーム、またはその他の任意の次元でターゲットにタグを付けます
- **構造の変更なし** - ディレクトリ構成を変更せずに組織的な構造を追加します
- **横断的な関心事** - 単一のターゲットが複数の論理グループに属することができます

### キャッシングとの統合

メタデータタグは <.localized_link href="/guides/features/cache">Tuist のキャッシング機能</.localized_link> とシームレスに連携します。

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## ベストプラクティス {#best-practices}

1. **シンプルに始める** - 単一のタグ付け次元（例：機能）から始め、必要に応じて拡張します
2. **一貫性を保つ** - すべてのマニフェストで同じ命名規則を使用します
3. **タグを文書化する** - 利用可能なタグとその意味のリストをプロジェクトのドキュメントに保持します
4. **ヘルパーを使用する** - プロジェクト記述ヘルパーを活用して、タグの適用を標準化します
5. **定期的に見直す** - プロジェクトの進化に合わせて、タグ付け戦略を見直し、更新します

## 関連機能 {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">コード共有</.localized_link> - プロジェクト記述ヘルパーを使用してタグの使用を標準化します
- <.localized_link href="/guides/features/cache">キャッシュ</.localized_link> - タグとキャッシングを組み合わせて、最適なビルドパフォーマンスを実現します
- <.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link> - 変更されたターゲットに対してのみテストを実行します
