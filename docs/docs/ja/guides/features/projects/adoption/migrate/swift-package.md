---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swiftパッケージを移行する{#migrate-a-swift-package}

Swift Package
Managerは、Swiftコードのための依存関係マネージャとして登場し、意図せずして、プロジェクトを管理し、Objective-Cのような他のプログラミング言語をサポートするという問題を解決することになった。このツールは異なる目的を念頭に置いて設計されたため、Tuistが提供する柔軟性、パフォーマンス、パワーを欠いているため、大規模なプロジェクトを管理するために使用するのは難しいかもしれません。これは[Scaling
iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)の記事でよく捉えられており、Swift
Package ManagerとネイティブのXcodeプロジェクトのパフォーマンスを比較した以下の表が含まれています：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift Package
Managerが同じようなプロジェクト管理の役割を果たせることを考えると、Tuistの必要性に異議を唱える開発者や組織にしばしば出くわす。ある者は移行を敢行し、後になって開発者のエクスペリエンスが著しく低下していることに気づく。例えば、ファイル名の変更に再インデックスに最大15秒かかるかもしれない。15秒だ！

**AppleがSwift Package Managerをビルドフォースケールのプロジェクトマネージャーにするかどうかは不明だ。**
しかし、そうなる兆候は見られない。実際、私たちは全く逆のことを見ている。彼らはXcodeに触発された決定をしており、暗黙的なコンフィギュレーションを通して利便性を達成しているようなものです。私たちは、Appleが第一原則に立ち返り、例えばプロジェクトを定義するインターフェイスとしてコンパイル言語を使用するなど、依存関係マネージャーとしては意味があってもプロジェクトマネージャーとしては意味がなかったいくつかの決定を見直す必要があると考えている。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
TuistはSwift Package
Managerを依存性マネージャーとして扱い、それは素晴らしいものだ。私たちは依存関係を解決し、それらをビルドするためにそれを使います。そのために設計されているわけではないので、プロジェクトを定義するために使うことはありません。
<!-- -->
:::

## Swift Package ManagerからTuistへの移行{#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager と Tuist の類似点は移行プロセスを簡単にします。主な違いは、`Package.swift`
の代わりにTuistのDSLを使ってプロジェクトを定義することです。

まず、`Package.swift` ファイルの隣に、`Project.swift` ファイルを作成します。`Project.swift`
ファイルには、プロジェクトの定義が含まれます。以下は、`Project.swift` ファイルの例で、1 つのターゲットを持つプロジェクトを定義しています：

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

いくつか注意すべきことがある：

- **ProjectDescription** ：`PackageDescription` を使う代わりに、`ProjectDescription`
  を使うことになる。
- **プロジェクト：** `パッケージ` インスタンスをエクスポートする代わりに、`プロジェクト` インスタンスをエクスポートします。
- **Xcode言語：**
  プロジェクトを定義するために使用するプリミティブは、Xcodeの言語を模倣しているため、スキーム、ターゲット、ビルドフェーズなどがあります。

次に、`Tuist.swift` ファイルを以下の内容で作成する：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`
にはプロジェクトの設定が含まれており、そのパスはプロジェクトのルートを決定するリファレンスとして機能します。Tuistプロジェクトの構造については<LocalizedLink href="/guides/features/projects/directory-structure">ディレクトリ構造</LocalizedLink>ドキュメントを参照してください。

## プロジェクトの編集{#editing-the-project}

1}`tuist
edit`を使って、Xcodeでプロジェクトを編集することができます。コマンドは、開いて作業を開始できるXcodeプロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模にもよりますが、一度に使用するか、段階的に使用するかを検討してください。DSLとワークフローに慣れるために、小さなプロジェクトから始めることをお勧めします。私たちのアドバイスは、常に、最も依存度の高いターゲットから始めて、トップレベルのターゲットまで作業することです。
