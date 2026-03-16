---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swiftパッケージの移行{#migrate-a-swift-package}

Swift Package
Managerは、Swiftコード用の依存関係管理ツールとして登場しましたが、意図せずしてプロジェクト管理やObjective-Cなどの他のプログラミング言語のサポートという課題を解決することになりました。このツールは当初異なる目的で設計されたため、Tuistが提供する柔軟性、パフォーマンス、および機能性に欠けており、大規模なプロジェクト管理に利用するのは困難な場合があります。
この点は、[Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)という記事によくまとめられており、そこにはSwift
Package ManagerとネイティブのXcodeプロジェクトのパフォーマンスを比較した以下の表が含まれています：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift Package
Managerでも同様のプロジェクト管理機能を利用できるため、Tuistの必要性を疑問視する開発者や組織によく遭遇します。中には移行を試みたものの、その後、開発体験が著しく低下したことに気づくケースもあります。例えば、ファイル名を変更した際、再インデックスに最大15秒かかることがあります。15秒もかかるのです！

**AppleがSwift Package Managerを大規模展開に適したプロジェクトマネージャーにするかどうかは定かではありません。**
しかし、それが実現する兆しは全く見られません。実際、その正反対の傾向が見られます。彼らはXcodeに倣った決定を下しており、例えば暗黙的な設定を通じて利便性を追求していますが、<LocalizedLink href="/guides/features/projects/cost-of-convenience">ご存知の通り、</LocalizedLink>これは大規模展開において複雑化の要因となります。
Appleが第一原理に立ち返り、依存関係管理ツールとしては理にかなっていたがプロジェクト管理ツールとしては不適切な決定（例えば、プロジェクト定義のインターフェースとしてコンパイル言語を使用することなど）を見直す必要があると考えています。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
TuistはSwift Package
Managerを依存関係管理ツールとして扱っており、これは非常に優れたツールです。私たちはこれを使用して依存関係を解決し、ビルドを行っています。ただし、プロジェクトの定義には使用しません。なぜなら、それはその目的のために設計されていないからです。
<!-- -->
:::

## Swift Package Manager から Tuist への移行{#migrating-from-swift-package-manager-to-tuist}

Swift Package ManagerとTuistには類似点が多いため、移行プロセスは簡単です。主な違いは、`Package.swift`
ではなく、TuistのDSLを使用してプロジェクトを定義する点です。

まず、`Package.swift` ファイルの隣に、`Project.swift` ファイルを作成します。`Project.swift`
ファイルには、プロジェクトの定義が含まれます。以下は、単一のターゲットを持つプロジェクトを定義する`Project.swift` ファイルの例です：

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

- **ProjectDescription**:`PackageDescription` の代わりに、`ProjectDescription` を使用します。
- **プロジェクト:** ` パッケージの` インスタンスをエクスポートする代わりに、`プロジェクトの` インスタンスをエクスポートすることになります。
- **Xcodeの用語:**
  プロジェクトを定義するために使用する基本要素はXcodeの用語に準拠しているため、schemes（スキーム）、targets（ターゲット）、build
  phases（ビルドフェーズ）などが含まれます。

次に、以下の内容で`Tuist.swift` ファイルを作成してください：

```swift
import ProjectDescription

let tuist = Tuist()
```

`のTuist.swift（`
）にはプロジェクトの設定が記述されており、そのパスはプロジェクトのルートを特定するための基準となります。Tuistプロジェクトの構造について詳しくは、<LocalizedLink href="/guides/features/projects/directory-structure">ディレクトリ構造</LocalizedLink>のドキュメントをご確認ください。

## プロジェクトの編集{#editing-the-project}

Xcodeでプロジェクトを編集するには、<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> を使用できます。このコマンドを実行すると、Xcodeプロジェクトが生成され、それを開いて作業を開始できます。

```bash
tuist edit
```

プロジェクトの規模によっては、一括で処理するか、段階的に処理するか検討してください。DSLやワークフローに慣れるため、まずは小規模なプロジェクトから始めることをお勧めします。常に、依存関係が最も強いターゲットから始め、トップレベルのターゲットに向かって順に処理していくことをお勧めします。
