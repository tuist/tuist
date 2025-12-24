---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# メタデータ・タグ{#metadata-tags}

プロジェクトの規模が大きくなり、複雑になってくると、コードベース全体を一度に扱うことは非効率になりかねない。Tuistは、開発中にターゲットを論理的なグループに整理し、プロジェクトの特定の部分に集中する方法として、**メタデータタグ**
を提供しています。

## メタデータ・タグとは？{#what-are-metadata-tags}

メタデータ・タグは、プロジェクトのターゲットに付けることができる文字列ラベルです。これらは、以下のことを可能にするマーカーとして機能する：

- **Group related targets** - 同じ機能、チーム、またはアーキテクチャレイヤーに属するターゲットをタグ付けする。
- **ワークスペースを絞り込む** - 特定のタグを持つターゲットのみを含むプロジェクトを生成する。
- **ワークフローの最適化** - コードベースの関連性のない部分をロードすることなく、特定の機能に取り組むことができます。
- **Select targets to keep as sources** - キャッシュ時にソースとして保持するターゲットのグループを選択する。

タグは、ターゲットの`メタデータ` プロパティを使用して定義され、文字列の配列として格納されます。

## メタデータ・タグの定義{#defining-metadata-tags}

プロジェクトマニフェスト内の任意のターゲットにタグを追加できます：

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

## タグ付けされたターゲットに焦点を当てる{#focusing-on-tagged-targets}

ターゲットにタグを付けたら、`tuist generate` コマンドを使って、特定のターゲットだけを含む集中プロジェクトを作成することができる：

### タグ別フォーカス

特定のタグにマッチするすべてのターゲットを含むプロジェクトを生成するには、`tag:` プレフィックスを使用します：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 名前でフォーカス

また、特定のターゲットを名指しでフォーカスすることもできる：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### フォーカスの仕組み

目標に集中する：

1. **Included targets** - クエリにマッチしたターゲットが生成されたプロジェクトに含まれる。
2. **依存関係** - フォーカスされたターゲットのすべての依存関係が自動的に含まれます。
3. **テストターゲット** - 焦点となるターゲットのテストターゲットが含まれる。
4. **Exclusion** - 他のすべてのターゲットをワークスペースから除外する。

つまり、機能開発に必要なものだけを収めた、より小さく管理しやすいワークスペースが手に入るのだ。

## タグの命名規則{#tag-naming-conventions}

どんな文字列でもタグとして使用できますが、一貫した命名規則に従うことで、タグを整理しておくことができます：

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

`feature:`,`team:`,`layer:` のような接頭辞を使うことで、各タグの目的を理解しやすくなり、名前の衝突を避けることができる。

## プロジェクト記述ヘルパーでタグを使う{#using-tags-with-helpers}

プロジェクト記述ヘルパーを活用することで、プロジェクト全体でタグの適用方法を標準化することができます：

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

そしてそれをマニフェストに使う：

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

## メタデータ・タグを使用するメリット{#benefits}

### 開発経験の向上

プロジェクトの特定の部分に集中することで、それが可能になる：

- **Xcodeプロジェクトのサイズを縮小** - より小さなプロジェクトで作業することで、開いたり移動したりするのが速くなります。
- **ビルドのスピードアップ** - 現在の仕事に必要なものだけをビルドする。
- **集中力の向上** - 関係のないコードに気を取られないようにする。
- **インデックス作成の最適化** - Xcodeはより少ないコードにインデックスを作成し、オートコンプリートを高速化します。

### より良いプロジェクト組織

タグはコードベースを整理する柔軟な方法を提供する：

- **複数のディメンション** - 機能、チーム、レイヤー、プラットフォーム、その他のディメンションでターゲットをタグ付けします。
- **構造変更なし** - ディレクトリのレイアウトを変更することなく、組織構造を追加。
- **横断的な関心事** - 1つのターゲットが複数の論理グループに属することがある。

### キャッシュとの統合

メタデータタグは<LocalizedLink href="/guides/features/cache">Tuistのキャッシュ機能</LocalizedLink>とシームレスに動作します：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## ベストプラクティス{#best-practices}。

1. **シンプルに始める** - 単一のタグ付けディメンション（例：フィーチャー）から始め、必要に応じて拡張する。
2. **一貫性を保つ** - すべてのマニフェストで同じ命名規則を使用する。
3. **タグを文書化する** - プロジェクトの文書に、利用可能なタグとその意味のリストを残す。
4. **ヘルパーの使用** - プロジェクト記述ヘルパーを活用し、タグの適用を標準化する。
5. **定期的な見直し** - プロジェクトの進展に合わせて、タグ戦略を見直し、更新する。

## 関連機能{#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">コードの共有</LocalizedLink> - プロジェクト記述ヘルパーを使用してタグの使用を標準化する
- <LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink> - タグとキャッシングを組み合わせて最適なビルドパフォーマンスを実現する
- <LocalizedLink href="/guides/features/selective-testing">選択的テスト</LocalizedLink> - 変更されたターゲットのみのテストを実行する