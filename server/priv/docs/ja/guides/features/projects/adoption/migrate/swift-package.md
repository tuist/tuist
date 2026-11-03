---
{
  "title": "Swift Package の移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Swift Package Manager によるプロジェクト管理から Tuist へ移行します。"
}
---
# Swift Package の移行 {#migrate-a-swift-package}

Swift Package Manager は Swift コードの依存関係マネージャーとして登場し、結果的にプロジェクト管理や Objective-C などの他のプログラミング言語のサポートという課題を解決する役割も担うようになりました。しかし、このツールは本来異なる目的で設計されたため、Tuist が提供する柔軟性、パフォーマンス、およびパワーに欠けており、大規模なプロジェクト管理には課題があります。この点は [Bumble での iOS スケーリング](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) という記事でよく説明されており、Swift Package Manager とネイティブな Xcode プロジェクトのパフォーマンスを比較した以下の表が含まれています。

<img style="max-width: 400px;" alt="SPM を使用した場合とネイティブな Xcode プロジェクトの場合のパフォーマンス低下を比較した表" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager が同様のプロジェクト管理の役割を果たせることを理由に、Tuist の必要性に疑問を抱く開発者や組織によく出会います。移行に着手したものの、後に開発者体験が著しく劣化したことに気づくケースもあります。例えば、ファイルの名前変更によって再インデックスに最大 15 秒かかることがあります。15 秒です！

**Apple が Swift Package Manager を大規模向けに最適化されたプロジェクトマネージャーにするかどうかは不透明です。** しかし、その動きを示す兆候は見られません。むしろ、逆の傾向が見られます。彼らは暗黙的な設定による利便性の追求など、Xcode に影響を受けた判断を下しており、<.localized_link href="/guides/features/projects/cost-of-convenience">ご存知のように</.localized_link>、これがスケール時の複雑さの原因となります。私たちは、Apple が根本原理に戻り、依存関係マネージャーとしては理にかなっていたがプロジェクトマネージャーとしては不適切だった一部の判断（例えば、プロジェクト定義のインターフェースとしてコンパイル言語を使用することなど）を見直す必要があると考えています。

> [!TIP]
> **依存関係マネージャーとしての SPM**
>
> Tuist は Swift Package Manager を依存関係マネージャーとして扱い、それは優れたツールです。私たちは依存関係の解決とビルドにそれを使用しています。プロジェクトの定義には使用しません。その目的で設計されていないためです。


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

注意点：

- **ProjectDescription**：`PackageDescription` の代わりに `ProjectDescription` を使用します。
- **Project：**`package` インスタンスをエクスポートする代わりに、`project` インスタンスをエクスポートします。
- **Xcode 言語：** プロジェクトを定義するために使用するプリミティブは Xcode の言語を模倣しているため、スキーム、ターゲット、ビルドフェーズなどが見つかります。

次に、以下の内容で `Tuist.swift` ファイルを作成します。

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` にはプロジェクトの設定が含まれており、そのパスはプロジェクトのルートを決定するための参照として機能します。Tuist プロジェクトの構造について詳しく知りたい場合は、<.localized_link href="/guides/features/projects/directory-structure">ディレクトリ構造</.localized_link> のドキュメントをご覧ください。

## プロジェクトの編集 {#editing-the-project}

<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> を使用して、Xcode でプロジェクトを編集できます。このコマンドは、開いて作業を開始できる Xcode プロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模に応じて、一括で実行するか、段階的に実行するかを検討してください。DSL とワークフローに慣れるために、小さなプロジェクトから始めることをお勧めします。私たちのアドバイスは、常に最も依存されているターゲットから始め、トップレベルのターゲットまで順に進めていくことです。
