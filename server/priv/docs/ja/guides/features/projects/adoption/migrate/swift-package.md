---
{
  "title": "Swift Package を移行する",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Swift Package Manager によるプロジェクト管理から Tuist へ移行します。"
}
---
# Swift Package の移行 {#migrate-a-swift-package}

Swift Package Manager は Swift コードの依存関係マネージャーとして登場しましたが、意図せずプロジェクト管理や Objective-C などの他のプログラミング言語のサポートという課題を解決する役割も担うようになりました。このツールは異なる目的を念頭に設計されているため、Tuist が提供する柔軟性、パフォーマンス、およびパワーに欠けることから、大規模なプロジェクト管理には課題が生じます。この点は [Bumble における iOS のスケーリング](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) の記事でよく説明されており、Swift Package Manager とネイティブ Xcode プロジェクトのパフォーマンスを比較した以下の表が含まれています。

<img style="max-width: 400px;" alt="SPM を使用した場合とネイティブ Xcode プロジェクトの場合のパフォーマンス低下を比較した表" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager が同様のプロジェクト管理の役割を果たせることを理由に Tuist の必要性に疑問を呈する開発者や組織によく出会います。移行に着手した後で、開発者体験が著しく劣化したことに気付くケースもあります。例えば、ファイルの名前変更により再インデックス作成に最大 15 秒かかることがあります。15 秒です！

**Apple が Swift Package Manager を大規模向けに最適化されたプロジェクトマネージャーにするかどうかは不明確です。** しかし、その兆候は見られません。むしろ、逆の傾向が見られます。暗黙的な設定によって利便性を実現するなど、Xcode に影響を受けた判断を下しており、<.localized_link href="/guides/features/projects/cost-of-convenience">ご存知のとおり</.localized_link>、これは大規模化に伴う複雑さの原因となります。私たちは、Apple が基本原理に戻り、依存関係マネージャーとしては理にかなっていたがプロジェクトマネージャーとしては不適切だったいくつかの判断（例えば、プロジェクト定義のインターフェースとしてコンパイル言語を使用することなど）を見直す必要があると考えています。

> [!TIP]
> **依存関係マネージャーとしての SPM**
>
> Tuist は Swift Package Manager を依存関係マネージャーとして扱っており、これは優れたツールです。私たちはこれを使用して依存関係を解決し、ビルドを行います。プロジェクト定義には使用しません。その目的で設計されていないためです。


## Swift Package Manager から Tuist への移行 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager と Tuist の類似性により、移行プロセスは簡単です。主な違いは、`Package.swift` の代わりに Tuist の DSL を使用してプロジェクトを定義することです。

まず、`Package.swift` ファイルの隣に `Project.swift` ファイルを作成します。`Project.swift` ファイルにはプロジェクトの定義が含まれます。単一のターゲットを持つプロジェクトを定義する `Project.swift` ファイルの例を以下に示します。

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

注意すべき点:

- **ProjectDescription**: `PackageDescription` を使用する代わりに、`ProjectDescription` を使用します。
- **Project:** `package` インスタンスをエクスポートする代わりに、`project` インスタンスをエクスポートします。
- **Xcode 言語:** プロジェクト定義に使用するプリミティブは Xcode の言語を模倣しているため、スキーム、ターゲット、ビルドフェーズなどが見つかります。

次に、以下の内容で `Tuist.swift` ファイルを作成します。

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` にはプロジェクトの設定が含まれており、そのパスはプロジェクトのルートを決定するための参照として機能します。Tuist プロジェクトの構造について詳しくは、<.localized_link href="/guides/features/projects/directory-structure">ディレクトリ構造</.localized_link> ドキュメントをご覧ください。

## プロジェクトの編集 {#editing-the-project}

<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> を使用して、Xcode でプロジェクトを編集できます。このコマンドは、開いて作業を開始できる Xcode プロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模に応じて、一括で実行するか、段階的に実行するかを検討してください。DSL とワークフローに慣れるために、小さなプロジェクトから始めることをお勧めします。私たちのアドバイスは、常に最も依存されているターゲットから始め、トップレベルのターゲットまで順に進めていくことです。
