---
{
  "title": "ベストプラクティス",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistで生成されたプロジェクトを扱う際のベストプラクティスを学びます。"
}
---
# ベストプラクティス {#best-practices}

さまざまなチームやプロジェクトでの長年の経験から、Tuist と Xcode プロジェクトを扱う際に推奨する一連のベストプラクティスを特定しました。これらのプラクティスは必須ではありませんが、プロジェクトの保守性と拡張性を高める構造にするのに役立ちます。

## Xcode {#xcode}

### 非推奨のパターン {#discouraged-patterns}

#### リモート環境をモデル化する構成 {#configurations-to-model-remote-environments}

多くの組織では、異なるリモート環境をモデル化するためにビルド構成を使用しています（例: `Debug-Production` や `Release-Canary`）。しかし、このアプローチにはいくつかの欠点があります。

- **不整合:** グラフ全体で構成に不整合があると、ビルドシステムが一部のターゲットに対して誤った構成を使用してしまう可能性があります。
- **複雑さ:** プロジェクトは、理解や保守が困難な多数のローカル構成とリモート環境のリストを抱え込むことになります。

ビルド構成は異なるビルド設定を表現するために設計されており、プロジェクトが必要とするのは通常 `Debug` と `Release` だけです。異なる環境をモデル化する必要性は、別の方法で実現できます。

- **Debug ビルドの場合:** 開発中にアクセス可能なすべての構成（エンドポイントなど）をアプリに含め、実行時に切り替えることができます。切り替えは、スキームの起動環境変数を使用するか、アプリ内の UI を介して行います。
- **Release ビルドの場合:** リリース時には、リリースビルドに紐づく構成のみを含め、コンパイラディレクティブを使用して構成を切り替えるための実行時ロジックを含めないようにします。

> [!NOTE]
> **標準以外の構成**
>
> Tuist は標準以外の構成をサポートし、通常の Xcode プロジェクトと比較して管理を容易にしますが、依存関係グラフ全体で構成が一貫していない場合、警告が表示されます。これにより、ビルドの信頼性が確保され、構成関連の問題を防ぐことができます。


## 生成されたプロジェクト

### ビルド可能フォルダ

Tuist 4.62.0 では、マージ競合を減らすために Xcode 16 で導入された機能である **ビルド可能フォルダ**（Xcode の同期グループ）のサポートが追加されました。

Tuist のワイルドカードパターン（例: `Sources/**/*.swift`）はすでに生成されたプロジェクトでのマージ競合を排除していますが、ビルド可能フォルダにはさらに次の利点があります。

- **自動同期**: プロジェクト構造がファイルシステムと同期した状態を保ち、ファイルの追加や削除時に再生成が不要になります
- **AI に適したワークフロー**: コーディングアシスタントやエージェントがプロジェクトの再生成をトリガーすることなくコードベースを変更できます
- **簡素化された構成**: 明示的なファイルリストを管理する代わりに、フォルダパスを定義します

よりスムーズな開発体験を得るため、従来の `Target.sources` および `Target.resources` 属性の代わりにビルド可能フォルダの採用を推奨します。

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

#### CI で解決済みバージョンを強制

CI で Swift Package Manager の依存関係をインストールする際は、決定論的ビルドを保証するために `--force-resolved-versions` フラグの使用を推奨します。

```bash
tuist install --force-resolved-versions
```

このフラグは、`Package.resolved` でピン留めされた正確なバージョンを使用して依存関係を解決することを保証し、依存関係解決における非決定性によって引き起こされる問題を排除します。これは、再現可能なビルドが重要な CI 環境で特に重要です。

#### GitHub Actions でのキャッシュされた依存関係のインストール {#dependency-cache-volumes}

生成されたプロジェクトの場合、[tuist/install](https://github.com/tuist/install) を使用して `Package.resolved` でピン留めされた依存関係をインストールし、実行間でキャッシュします。Tuist Runners では自動的に <.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> が使用され、他のランナーでは GitHub のキャッシュが使用されます。

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

サブディレクトリにあるプロジェクトの場合、チェックアウトからの相対パスを指定します。

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

その他のオプションについては、[アクションのリファレンス](https://github.com/tuist/install#usage) を参照してください。

### エージェンティックコーディングとワークツリー {#agentic-coding-and-worktrees}

コーディングエージェントと人間の貢献者はますます並行して作業しています。開発者はレビュー中の機能のためにワークツリーを開いたままにし、一方で1つ以上のエージェントが兄弟ワークツリーの独自のブランチで反復作業を行います。いくつかのプロジェクト選択により、これをよりスムーズに行えます。

#### エージェント主導の編集にビルド可能フォルダを使用する {#worktrees-buildable-folders}

エージェントがファイルを追加または削除する場合、`Project.swift` のファイルリストに依存するものは、プロジェクトが再びビルドされる前に `tuist generate` が必要です。[ビルド可能フォルダ](#buildable-folders) はその責任を Xcode の同期グループに移譲するため、ファイルツリーの編集が再生成をトリガーしなくなります。

これを `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link> と組み合わせます。このスキルは、エージェントに Tuist プロジェクトの日常的なワークフローを教えます。

#### ワークツリーごとにキャッシュを隔離しない {#worktrees-shared-cache}

Tuist は <.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link> に従っているため、デフォルトでは同じマシン上のすべてのワークツリーが `~/.cache/tuist` と `~/.local/state/tuist` を共有します。これが望ましい状態です。あるワークツリーでコンパイルされたヘルパー、別のワークツリーでダウンロードされたプラグイン、そして3番目のワークツリーで取得されたモジュールキャッシュのバイナリはすべて再利用可能です。

ワークツリー間での並列 `tuist` 呼び出しは安全に実行できます。特定の隔離が必要な場合を除き、`TUIST_XDG_CACHE_HOME` をワークツリー固有のパスに向けないでください。そうしないと、すべてのワークツリーでヘルパー、プラグイン、バイナリの再ウォームアップが強制されます。

#### SwiftPM のスクラッチ領域をワークツリーごとに保持する {#worktrees-swiftpm-scratch}

Swift Package Manager には独自のパス制御があります。`--scratch-path` は変更可能な作業状態で、デフォルトは `.build` です。一方、`--cache-path` は共有キャッシュディレクトリです。複数のワークツリーがアクティブな場合、これら2つのパスを同じように扱ってはなりません。

Tuist のデフォルトの `tuist install` 動作では、SwiftPM のスクラッチ領域がパッケージディレクトリ下に保持されるため、各ワークツリーは独自の `.build` を持ちます。この隔離を維持してください。単一の共有 SwiftPM スクラッチディレクトリを使用すると、無関係なブランチからのチェックアウト、ビルド中間ファイル、プラグイン、マクロ、ロックファイルが混在する可能性があります。

`Tuist.swift` で `installOptions` を介して、または `tuist install -- ...` を介して SwiftPM 引数を渡す場合、依存関係の取得を高速化したいときは `--cache-path` を共有しますが、`--scratch-path` は未設定のままにするか、ワークツリー固有のディレクトリを指定してください:

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

Xcode、Swift ツールチェーン、またはプラットフォームによってキャッシュパスを変更する必要がある場合は、ラッパーまたは CI 環境変数を使用してください。共有された `--scratch-path` をリポジトリにコミットしないでください。

あるワークツリーでのみ依存関係の状態が破損しているように見える場合は、そのワークツリーの `.build` ディレクトリを削除し、`tuist install` を再度実行してください。ワークツリー間で共有されている SwiftPM キャッシュ自体に疑わしい点がある場合は、依存関係を再インストールする前に `swift package purge-cache` を使用してください。

#### モジュールキャッシュを活用する {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> により、並列ワークツリーの実現が可能になります。Tuist は各ターゲットに対して決定論的な <.localized_link href="/guides/features/projects/hashing">ハッシュ</.localized_link> を計算するため、履歴の大部分を共有するブランチを指す2つのワークツリーは同じバイナリをヒットします。CI から `main` へのすべてのコミットで `tuist cache` を実行してください。ローカルでは、各ワークツリー内の `tuist generate` がキャッシュから可能な限り取得し、実際にブランチが変更した部分のみをビルドします。

キャッシュヒットを期待していたのにワークツリーがソースビルドにフォールバックする場合は、<.localized_link href="/guides/features/projects/hashing#debugging">ハッシュのデバッグ手順</.localized_link> に従ってください。非決定論的なハッシュ（通常はプロジェクト内の絶対パスが原因）が最も一般的な原因であり、2つのワークツリーを比較すると顕著に現れます。

#### レジストリを使用して Swift Package の解決を高速化する {#worktrees-registry}

各ワークツリーは Swift パッケージを独立して解決します。大規模な依存関係グラフを持つプロジェクトでは、これがすぐに累積されます。<.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> に切り替えることで、git 履歴の再クローンを回避し、解決時間を数分から数秒に短縮できます。

#### エージェントにプロジェクトの洞察を提供する {#worktrees-mcp}

多数のワークツリーでビルドとテストが実行されると、エージェントが行える最も有用なことは、*どの* 実行が回帰したか、どのテストが不安定か、バンドルサイズがどのように変化したかを推論することです。Tuist はそのデータを <.localized_link href="/guides/features/agentic-coding/mcp">MCP サーバー</.localized_link> および <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> パッケージを通じて公開しています。ワークフローごとに1つを選択し、それに固執してください。同じタスクで両方を混在させると、エージェントの動作に一貫性がなくなる傾向があります。

## 関連情報 {#related}

大規模な生成プロジェクトの適用に関するチームの経験については、[Monzo が Tuist で成長するモジュラープロジェクトの一貫性を保つ方法](https://tuist.dev/customers/monzo) をご覧ください。
