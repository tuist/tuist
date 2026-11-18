---
{
  "title": "Swift Package の移行",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Swift Package Manager によるプロジェクト管理から Tuist へ移行します。"
}
---
# Swift Package の移行 {#migrate-a-swift-package}

Swift Package Manager は Swift コードの依存関係マネージャーとして登場しましたが、意図せずプロジェクト管理や Objective-C といった他のプログラミング言語のサポートという課題を解決する役割も担うようになりました。このツールは異なる目的を念頭に設計されているため、Tuist が提供する柔軟性、パフォーマンス、およびパワーが不足しており、大規模なプロジェクト管理には課題が生じます。この点は [Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) の記事でよく説明されており、Swift Package Manager とネイティブ Xcode プロジェクトのパフォーマンスを比較した以下の表が含まれています。

<img style="max-width: 400px;" alt="SPM を使用した場合とネイティブ Xcode プロジェクトの場合のパフォーマンス低下を比較した表" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager が同様のプロジェクト管理ロールを果たせることから、Tuist の必要性に疑問を呈する開発者や組織によく出会います。移行に着手した後で、開発者体験が大幅に劣化したことに気付くケースもあります。例えば、ファイルの名前変更によって再インデックスに最大 15 秒かかることがあります。15 秒です。

**Apple が Swift Package Manager を大規模向けに設計されたプロジェクトマネージャーにするかどうかは不透明です。** しかし、その兆候は見られません。むしろ逆の傾向が見られます。暗黙的な構成によって利便性を実現するなど、Xcode に影響を受けた判断を下しており、<.localized_link href="/guides/features/projects/cost-of-convenience">ご存知のとおり、</.localized_link>これがスケール時の複雑さの原因となります。Apple が第一原理に戻り、依存関係マネージャーとしては妥当でもプロジェクトマネージャーとしては不適切だった一部の判断、たとえばプロジェクト定義のインターフェースとしてコンパイル言語を使用することなどを見直す必要があると考えています。

> [!TIP]
> **依存関係マネージャーとしての SwiftPM**
>
> Tuist は Swift Package Manager を依存関係マネージャーとして扱い、これは優れたツールです。私たちはこれを使って依存関係を解決し、ビルドします。プロジェクト定義には使用しません。その目的で設計されていないためです。


## Swift Package Manager から Tuist への移行 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager と Tuist の類似性により、移行プロセスはシンプルです。主な違いは、`Package.swift` の代わりに Tuist の DSL を使ってプロジェクトを定義することです。

まず、`Package.swift` ファイルと同じ場所に `Project.swift` ファイルを作成します。`Project.swift` ファイルにはプロジェクトの定義が含まれます。単一のターゲットを持つプロジェクトを定義する `Project.swift` ファイルの例を次に示します。

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

注意点:

- **ProjectDescription**: `PackageDescription` の代わりに `ProjectDescription` を使用します。
- **Project:** `package` インスタンスをエクスポートする代わりに、`project` インスタンスをエクスポートします。
- **Xcode 言語:** プロジェクト定義に使用するプリミティブは Xcode の言語を模倣しているため、スキーム、ターゲット、ビルドフェーズなどが用意されています。

次に、以下の内容で `Tuist.swift` ファイルを作成します。

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` にはプロジェクトの構成が含まれており、そのパスがプロジェクトのルートを決定するための基準となります。Tuist プロジェクトの構造について詳しくは、<.localized_link href="/guides/features/projects/directory-structure">ディレクトリ構造</.localized_link> のドキュメントをご覧ください。

## プロジェクトの編集 {#editing-the-project}

<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> を使用して、Xcode でプロジェクトを編集できます。このコマンドは、開いて作業を開始できる Xcode プロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模に応じて、一括で実行するか段階的に進めるかを選択できます。DSL とワークフローに慣れるために、小さなプロジェクトから始めることをお勧めします。私たちのアドバイスは常に、最も依存されているターゲットから始め、トップレベルのターゲットまで順に進めることです。
