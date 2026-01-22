---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swiftパッケージの移行{#migrate-a-swift-package}

Swift Package
ManagerはSwiftコード用の依存関係管理ツールとして登場しましたが、意図せずプロジェクト管理やObjective-Cなどの他プログラミング言語のサポートという課題も解決するようになりました。このツールは当初異なる目的で設計されたため、Tuistが提供する柔軟性・パフォーマンス・機能性に欠け、大規模プロジェクト管理には課題があります。
この点は[Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)の記事で明確に示されており、Swift
Package ManagerとネイティブXcodeプロジェクトのパフォーマンスを比較した以下の表が含まれています：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift Package
Managerが同様のプロジェクト管理機能を果たし得ることを考慮し、Tuistの必要性に疑問を呈する開発者や組織にしばしば遭遇します。移行を試みた後、開発者体験が著しく低下したことに気付くケースもあります。例えば、ファイル名変更後の再インデックスに最大15秒かかる場合があります。15秒です！

**AppleがSwift Package Managerをスケーラビリティ重視のプロジェクト管理ツールにするかは不透明だ。**
しかし現時点でその兆候は見られない。むしろ逆の傾向が顕著である。暗黙的な設定による利便性追求など、Xcode的な判断が繰り返されているが、<LocalizedLink href="/guides/features/projects/cost-of-convenience">ご存知の通り</LocalizedLink>、これは大規模環境では複雑化の根源となる。
Appleが第一原理に立ち返り、依存関係管理ツールとしては妥当でもプロジェクト管理ツールとしては不適切な決定（例えばプロジェクト定義インターフェースとしてコンパイル言語を使用する点など）を見直す必要があると考えています。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
TuistはSwift Package
Managerを依存関係管理ツールとして扱っており、非常に優れたツールです。依存関係の解決やビルドに利用しますが、プロジェクト定義には使用しません。そのための設計ではないためです。
<!-- -->
:::

## Swift Package Manager から Tuist への移行{#migrating-from-swift-package-manager-to-tuist}

Swift Package
ManagerとTuistの類似性により、移行プロセスは容易です。主な違いは、プロジェクトを`の`Package.swift`ではなくTuistのDSLで定義する点です。`

まず、`のProject.swift` ファイルを、`のPackage.swift` ファイルの隣に作成します。`のProject.swift`
ファイルにはプロジェクトの定義が含まれます。以下は単一ターゲットを持つプロジェクトを定義する`のProject.swift` ファイルの例です：

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
- **プロジェクト:** ` パッケージ` のインスタンスをエクスポートする代わりに、`プロジェクト` のインスタンスをエクスポートします。
- **Xcode言語:** プロジェクト定義に使用するプリミティブはXcodeの言語を模倣しているため、schemes、targets、build
  phasesなどが存在します。

次に、以下の内容で`Tuist.swiftファイルを作成してください：`

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`
にはプロジェクトの設定が含まれており、そのパスはプロジェクトのルートを決定するための参照として機能します。Tuistプロジェクトの構造について詳しくは、<LocalizedLink href="/guides/features/projects/directory-structure">ディレクトリ構造</LocalizedLink>のドキュメントを参照してください。

## プロジェクトの編集{#editing-the-project}

<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>
を使用して、Xcodeでプロジェクトを編集できます。このコマンドは、開いて作業を開始できるXcodeプロジェクトを生成します。

```bash
tuist edit
```

プロジェクトの規模に応じて、一括処理または段階的な処理を検討してください。DSLとワークフローに慣れるため、小規模なプロジェクトから始めることを推奨します。常に依存度の高いターゲットから開始し、最上位ターゲットまで段階的に進めることをお勧めします。
