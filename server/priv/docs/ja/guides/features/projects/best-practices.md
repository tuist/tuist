---
{
  "title": "ベストプラクティス",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist で生成されたプロジェクトを扱う際のベストプラクティスを学びます。"
}
---
# ベストプラクティス {#best-practices}

さまざまなチームやプロジェクトでの経験から、TuistおよびXcodeプロジェクトで推奨する一連のベストプラクティスを特定しました。これらの実践は必須ではありませんが、保守性と拡張性を高めるプロジェクト構造の構築に役立ちます。

## Xcode {#xcode}

### 推奨されないパターン {#discouraged-patterns}

#### リモート環境をモデル化する構成 {#configurations-to-model-remote-environments}

多くの組織では、異なるリモート環境をモデル化するためにビルド構成を使用しています（例: `Debug-Production` や `Release-Canary`）。しかし、このアプローチにはいくつかの欠点があります。

- **不整合:** グラフ全体に構成の不整合があると、ビルドシステムが一部のターゲットに対して誤った構成を使用してしまう可能性があります。
- **複雑さ:** プロジェクトには、理解や保守が困難な多数のローカル構成とリモート環境のリストが含まれてしまうことがあります。

ビルド構成は異なるビルド設定を表現するために設計されており、プロジェクトで必要なのは通常 `Debug` と `Release` だけです。異なる環境をモデル化する必要性は、別の方法で実現できます。

- **Debug ビルドの場合:** 開発中にアクセスすべきすべての構成（エンドポイントなど）をアプリに含め、実行時に切り替えることができます。切り替えは、スキームの起動環境変数を使用するか、アプリ内のUIで行うことができます。
- **Release ビルドの場合:** リリース時には、リリースビルドに紐づけられた構成のみを含め、コンパイラディレクティブを使用して構成切り替えの実行時ロジックを含めないようにすることができます。

> [!NOTE]
> **非標準の構成**
>
> Tuistは非標準の構成をサポートし、通常のXcodeプロジェクトよりも管理を容易にしますが、依存関係グラフ全体で構成に一貫性がない場合は警告が表示されます。これにより、ビルドの信頼性が確保され、構成関連の問題を防ぐことができます。


## 生成されたプロジェクト

### ビルド可能フォルダ

Tuist 4.62.0では、マージ競合を減らすためにXcode 16で導入された機能である**ビルド可能フォルダ**（Xcodeの同期グループ）のサポートが追加されました。

Tuistのワイルドカードパターン（例: `Sources/**/*.swift`）は生成されたプロジェクトにおけるマージ競合をすでに解消していますが、ビルド可能フォルダにはさらに次の利点があります。

- **自動同期**: プロジェクト構造がファイルシステムと同期した状態を保ち、ファイルの追加や削除時に再生成が不要になります
- **AIに適したワークフロー**: コーディングアシスタントやエージェントがプロジェクトの再生成をトリガーすることなくコードベースを変更できます
- **設定の簡素化**: 明示的なファイルリストを管理する代わりにフォルダパスを定義します

より効率的な開発体験を得るため、従来の `Target.sources` および `Target.resources` 属性の代わりにビルド可能フォルダの採用を推奨します。

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 依存関係

#### CIで解決済みバージョンを強制する

CIでSwift Package Managerの依存関係をインストールする際は、決定論的ビルドを保証するため `--force-resolved-versions` フラグの使用を推奨します。

```bash
tuist install --force-resolved-versions
```

このフラグにより、`Package.resolved` でピン留めされた正確なバージョンを使用して依存関係が解決され、依存関係解決の非決定性による問題が解消されます。再現可能なビルドが重要なCI環境では特に重要です。

#### GitHub Actionsでの依存関係キャッシュインストール {#dependency-cache-volumes}

生成されたプロジェクトでは、[tuist/install](https://github.com/tuist/install) を使用して `Package.resolved` でピン留めされた依存関係をインストールし、実行間でキャッシュします。Tuist Runnersでは自動的に <.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link> が使用され、他のランナーではGitHubのキャッシュが使用されます。

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

その他のオプションについては、[アクションリファレンス](https://github.com/tuist/install#usage) を参照してください。

### エージェンティックコーディングとワークツリー {#agentic-coding-and-worktrees}

コーディングエージェントと人間の貢献者はますます並行して作業を行っています。開発者はレビュー中の機能のためにワークツリーを開いたままにし、1つ以上のエージェントが兄弟ワークツリーの各自のブランチで反復処理を行います。いくつかのプロジェクト選択により、これを大幅に円滑にできます。

#### エージェント主導の編集にビルド可能フォルダを使用する {#worktrees-buildable-folders}

エージェントがファイルを追加または削除すると、`Project.swift` のファイルリストに依存するものはすべて、プロジェクトが再びビルドされる前に `tuist generate` が必要です。[ビルド可能フォルダ](#buildable-folders) はその責任をXcodeの同期グループに委譲するため、ファイルツリーの編集はもはや再生成をトリガーしません。

これを `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link> と組み合わせることで、エージェントにTuistプロジェクトの日常的なワークフローを教えます。

#### ワークツリーごとにキャッシュを隔離しない {#worktrees-shared-cache}

Tuistは <.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link> に従っているため、デフォルトでは同じマシン上のすべてのワークツリーが `~/.cache/tuist` と `~/.local/state/tuist` を共有します。これが望ましい状態です。あるワークツリーでコンパイルされたヘルパー、別のワークツリーでダウンロードされたプラグイン、さらに別のワークツリーで取得されたモジュールキャッシュのバイナリは、すべて再利用可能です。

ワークツリー間での並列 `tuist` 呼び出しは安全に実行できます。特に隔離が必要な場合を除き、`TUIST_XDG_CACHE_HOME` をワークツリーローカルのパスに向けないでください。そうしないと、すべてのワークツリーでヘルパー、プラグイン、バイナリを再度ウォームアップする必要が生じます。

#### SwiftPMのスクラッチ領域をワークツリーごとに維持する {#worktrees-swiftpm-scratch}

Swift Package Managerには独自のパス制御があります。`--scratch-path` は変更可能な作業状態で、デフォルトは `.build` です。一方、`--cache-path` は共有キャッシュディレクトリです。複数のワークツリーがアクティブな場合、これら2つのパスを同じように扱うべきではありません。

Tuistのデフォルトの `tuist install` 動作では、SwiftPMのスクラッチ領域はパッケージディレクトリ下に保持されるため、各ワークツリーは独自の `.build` を持ちます。この隔離を維持してください。単一の共有SwiftPMスクラッチディレクトリを使用すると、無関係なブランチからのチェックアウト、ビルド中間ファイル、プラグイン、マクロ、およびロックファイルが混在する可能性があります。

SwiftPM引数を `tuist install -- ...` または `Tuist.swift` 内の `installOptions` を介して渡す場合、依存関係の取得を高速化したいときは `--cache-path` を共有しますが、`--scratch-path` は未設定のままにするか、ワークツリーローカルのディレクトリを指すようにしてください:

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

キャッシュパスがXcode、Swiftツールチェーン、またはプラットフォームによって異なる必要がある場合は、ラッパーまたはCI環境変数を使用してください。共有 `--scratch-path` をリポジトリにコミットしないでください。

あるワークツリーでのみ依存関係の状態が破損しているように見える場合は、そのワークツリーの `.build` ディレクトリを削除して `tuist install` を再度実行してください。ワークツリー間で共有SwiftPMキャッシュ自体が疑わしい場合は、依存関係を再インストールする前に `swift package purge-cache` を使用してください。

#### モジュールキャッシュを活用する {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> が並列ワークツリーの実現を可能にします。Tuistは各ターゲットに対して決定論的な <.localized_link href="/guides/features/projects/hashing">ハッシュ</.localized_link> を計算するため、履歴の大部分を共有するブランチを指す2つのワークツリーは同じバイナリにヒットします。CIから `main` へのすべてのコミットで `tuist cache` を実行してください。ローカルでは、各ワークツリーでの `tuist generate` がキャッシュから可能なものを取得し、ブランチが実際に変更した部分のみをビルドします。

キャッシュヒットが期待されるのにワークツリーがソースビルドにフォールバックする場合は、<.localized_link href="/guides/features/projects/hashing#debugging">ハッシュのデバッグ手順</.localized_link> に従ってください。非決定論的ハッシュ（通常はプロジェクト内の絶対パスが原因）が最も一般的な原因であり、2つのワークツリーを比較すると顕著に現れます。

#### レジストリを使用してSwift Packageの解決を高速化する {#worktrees-registry}

各ワークツリーはSwiftパッケージを独立して解決します。大規模な依存関係グラフを持つプロジェクトでは、これがすぐに累積されます。<.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> に切り替えることで、git履歴の再クローンを回避し、解決時間を数分から数秒に短縮できます。

#### エージェントにプロジェクトの洞察を提供する {#worktrees-mcp}

多くのワークツリーでビルドとテストが実行されると、エージェントが行える最も有用なことは、*どの*実行で回帰が発生したか、どのテストがflakyか、バンドルサイズがどのように変化したかを推論することです。Tuistはそのデータを <.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link> および <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> パッケージを通じて公開しています。ワークフローごとに1つを選択し、それを一貫して使用してください。同じタスクで両方を混合すると、エージェントの動作に一貫性がなくなる傾向があります。
