---
{
  "title": "Swift Package の移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Swift Package Manager によるプロジェクト管理から Tuist に移行します。"
}
---
# Swift Package を移行する {#migrate-a-swift-package}

Swift Package Manager は Swift コードの依存関係マネージャーとして登場しましたが、意図せずしてプロジェクト管理や Objective-C といった他のプログラミング言語のサポートという課題を解決する役割も担うようになりました。このツールは本来異なる目的で設計されているため、Tuist が提供する柔軟性、パフォーマンス、およびパワーに欠けることから、大規模なプロジェクト管理には課題が生じます。この点は [Bumble での iOS スケーリング](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) の記事でよく説明されており、Swift Package Manager とネイティブな Xcode プロジェクトのパフォーマンスを比較した以下の表が掲載されています。

<img style="max-width: 400px;" alt="SPM を使用した場合とネイティブな Xcode プロジェクトの場合のパフォーマンス劣化を比較した表" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager が同様のプロジェクト管理の役割を果たせることを理由に、Tuist の必要性に疑問を抱く開発者や組織によく出会います。移行に着手したものの、後に開発者体験が大幅に低下したことに気付くケースもあります。例えば、ファイルの名前変更だけで再インデックスに最大 15 秒かかることがあります。15 秒です！

**Apple が Swift Package Manager を大規模向けに設計されたプロジェクトマネージャーにするかどうかは不明です。** しかし、その兆候は見られません。むしろ、逆の傾向が見られます。暗黙的な設定によって利便性を実現するなど、Xcode に影響を受けた判断を下しており、<.localized_link href="/guides/features/projects/cost-of-convenience">ご存知のとおり、</.localized_link>これは大規模化における複雑さの原因となります。Apple が根本原則に戻り、依存関係マネージャーとしては妥当だがプロジェクトマネージャーとしては不適切だった一部の判断（例えば、プロジェクト定義のインターフェースとしてコンパイル済み言語を使用することなど）を見直す必要があると考えています。

> [!TIP]
> **依存関係マネージャーとしての SwiftPM**
>
> Tuist は Swift Package Manager を依存関係マネージャーとして扱っており、それは優れたものです。依存関係の解決とビルドに利用していますが、プロジェクト定義には使用していません。その目的で設計されていないためです。並列比較については、[Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager) を参照してください。


## Swift Package Manager から Tuist への移行 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager と Tuist の類似性により、移行プロセスは簡単です。主な違いは、`Package.swift` の代わりに Tuist の DSL を使用してプロジェクトを定義することです。

まず、`Package.swift` ファイルの隣に `Project.swift` ファイルを作成します。`Project.swift` ファイルにはプロジェクトの定義が含まれます。単一のターゲットを持つプロジェクトを定義する `Project.swift` ファイルの例を次に示します。

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
- **Xcode の言語：** プロジェクト定義に使用するプリミティブは Xcode の言語を模倣しているため、スキーム、ターゲット、ビルドフェーズなどが見つかります。

次に、以下の内容で `Tuist.swift` ファイルを作成します。

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` にはプロジェクトの設定が含まれており、そのパスはプロジェクトのルートを決定するための参照として機能します。Tuist プロジェクトの構造について詳しくは、<.localized_link href="/guides/features/projects/directory-structure">ディレクトリ構造</.localized_link> のドキュメントを確認してください。

## プロジェクトの編集 {#editing-the-project}

<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> を使用して、Xcode でプロジェクトを編集できます。このコマンドは、開いて作業を開始できる Xcode プロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模に応じて、一括で実行するか段階的に実行するかを検討してください。DSL とワークフローに慣れるために、小さなプロジェクトから始めることをお勧めします。私たちのアドバイスは常に、最も依存されているターゲットから始め、トップレベルのターゲットまで順に進めていくことです。
