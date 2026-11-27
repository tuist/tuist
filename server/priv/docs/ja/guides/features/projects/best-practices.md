---
{
  "title": "ベストプラクティス",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist で生成されたプロジェクトを扱う際のベストプラクティスを学びます。"
}
---
# ベストプラクティス {#best-practices}

さまざまなチームやプロジェクトでの経験から、Tuist および Xcode プロジェクトに取り組む際に推奨するベストプラクティスを特定しました。これらのプラクティスは必須ではありませんが、プロジェクトの保守性と拡張性を高める構造にするのに役立ちます。

## Xcode {#xcode}

### 非推奨のパターン {#discouraged-patterns}

#### リモート環境をモデル化するためのコンフィギュレーション {#configurations-to-model-remote-environments}

多くの組織では、異なるリモート環境をモデル化するためにビルドコンフィギュレーションを使用しています（例: `Debug-Production` や `Release-Canary`）。しかし、このアプローチにはいくつかの欠点があります。

- **不整合:** グラフ全体にコンフィギュレーションの不整合がある場合、ビルドシステムが一部のターゲットに対して間違ったコンフィギュレーションを使用してしまう可能性があります。
- **複雑さ:** プロジェクトは、理解や保守が困難なローカルコンフィギュレーションとリモート環境の長いリストを抱えることになりがちです。

ビルドコンフィギュレーションは異なるビルド設定を表すために設計されており、プロジェクトが必要とするのは通常 `Debug` と `Release` だけです。異なる環境をモデル化する必要性は、別の方法で実現できます。

- **Debug ビルドの場合:** 開発中にアクセス可能なすべてのコンフィギュレーション（エンドポイントなど）をアプリに含め、ランタイム時に切り替えることができます。切り替えは、スキームの起動環境変数を使用するか、アプリ内の UI を介して行います。
- **Release ビルドの場合:** リリース時には、リリースビルドに紐付けられたコンフィギュレーションのみを含め、コンパイラディレクティブを使用してコンフィギュレーションを切り替えるためのランタイムロジックを含めないようにします。

> [!NOTE]
> **非標準のコンフィギュレーション**
>
> Tuist は非標準のコンフィギュレーションをサポートし、通常の Xcode プロジェクトと比較して管理を容易にしますが、依存関係グラフ全体でコンフィギュレーションに一貫性がない場合は警告が表示されます。これにより、ビルドの信頼性が確保され、コンフィギュレーション関連の問題を防ぐことができます。


## 生成されたプロジェクト

### ビルド可能フォルダ

Tuist 4.62.0 では、マージ競合を減らすために Xcode 16 で導入された機能である **ビルド可能フォルダ**（Xcode の同期グループ）のサポートが追加されました。

Tuist のワイルドカードパターン（例: `Sources/**/*.swift`）は生成されたプロジェクトにおけるマージ競合をすでに排除していますが、ビルド可能フォルダにはさらに次のような利点があります。

- **自動同期**: プロジェクト構造がファイルシステムと同期した状態を保ちます。ファイルの追加や削除時に再生成は不要です。
- **AI に適したワークフロー**: コーディングアシスタントやエージェントが、プロジェクトの再生成をトリガーすることなくコードベースを変更できます。
- **シンプルなコンフィギュレーション**: 明示的なファイルリストを管理する代わりに、フォルダパスを定義します。

よりスムーズな開発体験のために、従来の `Target.sources` および `Target.resources` 属性の代わりにビルド可能フォルダの採用を推奨します。

::: code-group

```swift [With buildable folders]
let target: Target = .target(
  name: "App",
  destinations: .iOS,
  product: .app,
  bundleId: "dev.tuist.App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target: Target = .target(
  name: "App",
  destinations: .iOS,
  product: .app,
  bundleId: "dev.tuist.App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 依存関係

#### CI 上で解決済みバージョンを強制する

CI 上で Swift Package Manager の依存関係をインストールする際は、決定論的なビルドを保証するために `--force-resolved-versions` フラグの使用を推奨します。

```bash
tuist install --force-resolved-versions
```

このフラグにより、`Package.resolved` にピン留めされた正確なバージョンを使用して依存関係が解決され、依存関係の解決における非決定論によって引き起こされる問題を排除します。再現可能なビルドが重要な CI では特に重要です。

#### GitHub Actions でのキャッシュされた依存関係のインストール {#dependency-cache-volumes}

生成されたプロジェクトの場合、[tuist/install](https://github.com/tuist/install) を使用して `Package.resolved` にピン留めされた依存関係をインストールし、実行間でキャッシュします。Tuist Runners では <.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> を、その他のランナーでは GitHub のキャッシュを自動的に使用します。

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

サブディレクトリにあるプロジェクトの場合は、チェックアウトからの相対パスを指定します。

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

追加のオプションについては、[アクションリファレンス](https://github.com/tuist/install#usage) を参照してください。

### エージェンティックコーディングとワークツリー {#agentic-coding-and-worktrees}

コーディングエージェントと人間の貢献者はますます並行して作業しています。開発者はレビュー中の機能のためにワークツリーを開いたままにし、一方、1 つ以上のエージェントは兄弟ワークツリー内の独自のブランチで反復作業を行います。いくつかのプロジェクト選択により、これを大幅にスムーズにできます。

#### エージェント主導の編集にビルド可能フォルダを使用する {#worktrees-buildable-folders}

エージェントがファイルを追加または削除する場合、`Project.swift` 内のファイルリストに依存するものは、プロジェクトが再びビルドされる前に `tuist generate` が必要です。[ビルド可能フォルダ](#buildable-folders) はその責任を Xcode の同期グループに移譲するため、ファイルツリーの編集が再生成をトリガーすることはなくなります。

これを `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link> と組み合わせます。このスキルは、Tuist プロジェクトの日々のワークフローをエージェントに教えます。

#### ワークツリーごとにキャッシュを隔離しない {#worktrees-shared-cache}

Tuist は <.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link> に従っているため、デフォルトでは同じマシン上のすべてのワークツリーが `~/.cache/tuist` と `~/.local/state/tuist` を共有します。これが望ましい状態です。あるワークツリーでコンパイルされたヘルパー、別のワークツリーでダウンロードされたプラグイン、そして第三のワークツリーで取得されたモジュールキャッシュのバイナリは、すべて再利用可能です。

ワークツリー間での並行する `tuist` 呼び出しは、並列実行しても安全です。特に隔離が必要な場合を除き、`TUIST_XDG_CACHE_HOME` をワークツリーローカルのパスに向けないでください。そうすると、すべてのワークツリーでヘルパー、プラグイン、バイナリの再ウォームアップが強制されます。

#### SwiftPM のスクラッチ領域をワークツリーごとに維持する {#worktrees-swiftpm-scratch}

Swift Package Manager には独自のパス制御があります。`--scratch-path` は変更可能な作業状態で、デフォルトは `.build` です。一方、`--cache-path` は共有キャッシュディレクトリです。複数のワークツリーがアクティブな場合、これら2つのパスを同じように扱ってはなりません。

Tuist のデフォルトの `tuist install` 動作では、SwiftPM のスクラッチ領域はパッケージディレクトリ内に保持されるため、各ワークツリーは独自の `.build` を持ちます。この隔離を維持してください。単一の共有 SwiftPM スクラッチディレクトリを使用すると、無関係なブランチからのチェックアウト、ビルド中間ファイル、プラグイン、マクロ、およびロックファイルが混在する可能性があります。

`tuist install -- ...` を介して、または `Tuist.swift` 内の `installOptions` を介して SwiftPM 引数を渡す場合、依存関係の取得を高速化したいときは `--cache-path` を共有しますが、`--scratch-path` は未設定のままにするか、ワークツリーローカルのディレクトリを指定してください。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

キャッシュパスが Xcode、Swift ツールチェーン、またはプラットフォームによって異なる必要がある場合は、ラッパーまたは CI 環境変数を使用してください。共有される `--scratch-path` をリポジトリにコミットしないでください。

あるワークツリーでのみ依存関係の状態が破損しているように見える場合は、そのワークツリーの `.build` ディレクトリを削除し、`tuist install` を再度実行してください。ワークツリー間で共有されている SwiftPM キャッシュ自体に疑わしい点がある場合は、依存関係を再インストールする前に `swift package purge-cache` を使用してください。

#### モジュールキャッシュを活用する {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> が並列ワークツリーの実現を可能にします。Tuist は各ターゲットに対して決定論的な <.localized_link href="/guides/features/projects/hashing">ハッシュ</.localized_link> を計算するため、履歴の大部分を共有するブランチを指す 2 つのワークツリーは同じバイナリをヒットします。CI から `main` へのすべてのコミットで `tuist cache` を実行してください。ローカルでは、各ワークツリーでの `tuist generate` がキャッシュから可能なものを取得し、ブランチが実際に変更した部分のみをビルドします。

キャッシュヒットを期待していたのにワークツリーがソースビルドに fallback した場合は、<.localized_link href="/guides/features/projects/hashing#debugging">ハッシュのデバッグ手順</.localized_link> に従ってください。非決定論的なハッシュ（通常はプロジェクト内の絶対パスが原因）が最も一般的な原因であり、2 つのワークツリーを比較すると顕著に現れます。

#### レジストリを使用して Swift Package の解決を高速化する {#worktrees-registry}

各ワークツリーは Swift パッケージを独立して解決します。大規模な依存関係グラフを持つプロジェクトでは、これがすぐに累積されます。<.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> に切り替えることで、git 履歴の再クローンを回避し、解決時間を数分から数秒に短縮できます。

#### エージェントにプロジェクトのインサイトへのアクセス権を与える {#worktrees-mcp}

多くのワークツリーでビルドとテストが実行されると、エージェントが行える最も有用なことは、それらの実行のうち *どれ* が回帰したか、どのテストが不安定か、バンドルサイズがどのように変化したかを推論することです。Tuist はそのデータを <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> および <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> パッケージを通じて公開しています。ワークフローごとに 1 つを選択し、それに固執してください。同じタスクで両方を混合すると、エージェントの動作に一貫性がなくなる傾向があります。

## 関連項目 {#related}

大規模な生成済みプロジェクトの適用に関するチームの経験については、[Tuist を使用して成長するモジュラープロジェクトの一貫性を保つ Monzo の方法](https://tuist.dev/customers/monzo) をお読みください。
