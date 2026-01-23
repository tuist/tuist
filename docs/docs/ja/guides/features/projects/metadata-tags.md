---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# メタデータタグ{#metadata-tags}

プロジェクトの規模と複雑さが増すにつれ、コードベース全体を一度に扱うことは非効率的になる可能性があります。Tuistは、ターゲットを論理的なグループに整理し、開発中にプロジェクトの特定部分に集中できるようにする方法として、**メタデータタグ**
を提供しています。

## メタデータタグとは何ですか？{#what-are-metadata-tags}

メタデータタグは、プロジェクト内のターゲットに付与できる文字列ラベルです。これらはマーカーとして機能し、以下のことを可能にします：

- **関連するターゲットをグループ化してください** - 同じ機能、チーム、またはアーキテクチャ層に属するターゲットにタグを付けてください
- **** - 特定のタグを持つターゲットのみを含むプロジェクトを生成
- **ワークフローを最適化** - コードベースの無関係な部分をロードせずに特定の機能に取り組む
- **ソースとして保持するターゲットを選択** - キャッシュ時にソースとして保持するターゲットグループを選択

タグは、ターゲットのメタデータプロパティ `` `（`）を使用して定義され、文字列の配列として保存されます。

## メタデータタグの定義{#defining-metadata-tags}

プロジェクトマニフェスト内の任意のターゲットにタグを追加できます:

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

## タグ付きターゲットに焦点を当てる{#focusing-on-tagged-targets}

ターゲットにタグ付けしたら、``` コマンドを使用して特定のターゲットのみを含むフォーカスされたプロジェクトを生成できます:`` `

### タグによるフォーカス

`タグを使用:` prefix で、特定のタグに一致するすべてのターゲットを含むプロジェクトを生成します:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 名前でフォーカス

特定のターゲットを名前で指定することも可能です：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### フォーカスの仕組み

ターゲットに焦点を当てる場合：

1. **含まれるターゲット** - クエリに一致するターゲットは生成されたプロジェクトに含まれます
2. **依存関係** - フォーカス対象のすべての依存関係が自動的に含まれます
3. **テスト対象** - フォーカス対象のテスト対象が含まれています
4. **除外** - その他のすべてのターゲットはワークスペースから除外されます

これにより、機能開発に必要な要素のみを含む、よりコンパクトで扱いやすい作業領域が実現します。

## タグ命名規則{#tag-naming-conventions}

タグには任意の文字列を使用できますが、一貫した命名規則に従うことでタグを整理しやすくなります:

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

``` のような接頭辞を使用すると、各タグの目的が理解しやすくなり、命名衝突を回避できます。例: (feature:)、 (team:)、または
(layer:)。` ` `

## システムタグ{#system-tags}

Tuistはシステム管理タグに`tuist:`
プレフィックスを使用します。これらのタグはTuistによって自動的に適用され、キャッシュプロファイルで生成される特定のコンテンツタイプをターゲットにする際に使用できます。

### 利用可能なシステムタグ

| Tag                 | 説明                                                                                                 |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| `tuist:synthesized` | Tuistが静的ライブラリおよび静的フレームワークのリソース処理用に生成する合成バンドル対象に適用されます。これらのバンドルは、リソースアクセサAPIを提供するための歴史的経緯から存在しています。 |

### キャッシュプロファイルでのシステムタグの使用

合成対象を含めるか除外するかについては、キャッシュプロファイルでシステムタグを使用できます:

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

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
合成バンドルターゲットは、親ターゲットからすべてのタグを継承するほか、`tuist:synthesized`
タグを受け取ります。つまり、静的ライブラリに`feature:auth` をタグ付けした場合、その合成リソースバンドルには`feature:auth`
と`tuist:synthesized` の両方のタグが付与されます。
<!-- -->
:::

## プロジェクト説明ヘルパーでのタグの使用方法{#using-tags-with-helpers}

プロジェクト全体でタグの適用方法を標準化するには、<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト説明ヘルパー</LocalizedLink>を活用できます:

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

その後、マニフェストで以下のように使用してください：

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

## メタデータタグを使用する利点{#benefits}

### 開発体験の向上

プロジェクトの特定部分に焦点を当てることで、次のことが可能になります：

- **Xcodeプロジェクトのサイズを縮小する** - 開く速度や操作性が向上した小型プロジェクトで作業する
- **ビルドを高速化** - 現在の作業に必要なものだけをビルドする
- **** の焦点を改善する - 関連性のないコードによる注意散漫を避ける
- **** のインデックス作成を最適化 - Xcodeがインデックス化するコード量を減らし、オートコンプリートを高速化

### プロジェクトの整理を改善する

タグはコードベースを整理する柔軟な方法を提供します:

- **複数次元の** - 機能、チーム、レイヤー、プラットフォーム、その他の次元でターゲットをタグ付けする
- **構造変更なし** - ディレクトリ構成を変更せずに組織構造を追加
- **横断的関心事** - 単一のターゲットが複数の論理グループに属することが可能

### キャッシュとの統合

メタデータタグは<LocalizedLink href="/guides/features/cache">Tuistのキャッシュ機能</LocalizedLink>とシームレスに連携します：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## ベストプラクティス{#best-practices}。

1. **シンプルに始める** - 単一のタグ付け次元（例：機能）から始め、必要に応じて拡張する
2. **一貫性を保つ** - すべてのマニフェストで同じ命名規則を使用する
3. **** - プロジェクトのドキュメントに、利用可能なタグとその意味の一覧を記載してください
4. **ヘルパーを使用する** - プロジェクト説明ヘルパーを活用し、タグ適用を標準化する
5. **定期的に見直す** - プロジェクトの進展に伴い、タグ付け戦略を見直し更新する

## 関連機能{#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">コード共有</LocalizedLink>
  - プロジェクト説明ヘルパーを使用してタグの使用を標準化する
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> -
  キャッシュ機能とタグを組み合わせて最適なビルドパフォーマンスを実現
- <LocalizedLink href="/guides/features/selective-testing">選択的テスト</LocalizedLink>
  - 変更されたターゲットのみテストを実行
