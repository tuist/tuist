---
{
  "title": "ベストプラクティス",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistで生成されたプロジェクトを扱う際のベストプラクティスを学びます。"
}
---
# ベストプラクティス {#best-practices}

さまざまなチームやプロジェクトでの経験を通じて、TuistおよびXcodeプロジェクトで採用することを推奨するベストプラクティスを特定しました。これらのプラクティスは必須ではありませんが、プロジェクトの保守性と拡張性を高める構造にするのに役立ちます。

## Xcode {#xcode}

### 推奨されないパターン {#discouraged-patterns}

#### リモート環境をモデル化する構成 {#configurations-to-model-remote-environments}

多くの組織では、異なるリモート環境をモデル化するためにビルド構成を使用しています（例：`Debug-Production`や`Release-Canary`）が、このアプローチにはいくつかの欠点があります。

- **不整合:** グラフ全体に構成の不整合がある場合、ビルドシステムが一部のターゲットに対して誤った構成を使用してしまう可能性があります。
- **複雑さ:** プロジェクトは、理解や保守が困難な多数のローカル構成とリモート環境のリストを抱え込むことになります。

ビルド構成は異なるビルド設定を表すために設計されており、プロジェクトが必要とするのは通常`Debug`と`Release`のみです。異なる環境をモデル化する必要性は、以下のように別の方法で実現できます。

- **Debugビルドの場合:** 開発中にアクセス可能なすべての構成（エンドポイントなど）をアプリに含め、ランタイム時に切り替えることができます。切り替えは、スキームの起動環境変数を使用するか、アプリ内のUIで行うことができます。
- **Releaseビルドの場合:** リリース時には、リリースビルドに紐づく構成のみを含め、コンパイラディレクティブを使用して構成切り替えのランタイムロジックを含めないようにすることができます。

> [!NOTE]
> **標準以外の構成**
>
> Tuistは標準以外の構成をサポートし、通常のXcodeプロジェクトと比較して管理を容易にしますが、依存関係グラフ全体で構成が一貫していない場合は警告が表示されます。これにより、ビルドの信頼性が確保され、構成関連の問題を防ぐことができます。


## 生成されたプロジェクト

### ビルド可能フォルダ

Tuist 4.62.0では、マージ競合を減らすためにXcode 16で導入された機能である**ビルド可能フォルダ**（Xcodeの同期グループ）のサポートが追加されました。

Tuistのワイルドカードパターン（例：`Sources/**/*.swift`）は生成されたプロジェクトにおけるマージ競合をすでに排除していますが、ビルド可能フォルダにはさらに以下の利点があります。

- **自動同期**: プロジェクト構造がファイルシステムと同期した状態を保ち、ファイルの追加や削除時に再生成が不要になります
- **AIに適したワークフロー**: コーディングアシスタントやエージェントがプロジェクトの再生成をトリガーすることなくコードベースを変更できます
- **設定の簡素化**: 明示的なファイルリストを管理する代わりにフォルダパスを定義します

より効率的な開発体験のために、従来の`Target.sources`および`Target.resources`属性の代わりにビルド可能フォルダの採用を推奨します。

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

CIでSwift Package Managerの依存関係をインストールする際は、決定論的ビルドを保証するために`--force-resolved-versions`フラグの使用を推奨します。

```bash
tuist install --force-resolved-versions
```

このフラグは、`Package.resolved`でピン留めされた正確なバージョンを使用して依存関係が解決されることを保証し、依存関係解決の非決定性によって引き起こされる問題を排除します。これは、再現可能なビルドが重要なCI環境で特に重要です。

#### GitHub Actionsでの依存関係インストールのキャッシュ {#dependency-cache-volumes}

生成されたプロジェクトの場合、[tuist/install](https://github.com/tuist/install)を使用して`Package.resolved`でピン留めされた依存関係をインストールし、実行間でキャッシュします。Tuist Runnersでは自動的に<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>を使用し、他のランナーではGitHubのキャッシュを使用します。

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

サブディレクトリにあるプロジェクトの場合は、チェックアウトからの相対パスを指定してください。

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

追加のオプションについては、[アクションリファレンス](https://github.com/tuist/install#usage)をご覧ください。

### エージェンティックコーディングとワークツリー {#agentic-coding-and-worktrees}

コーディングエージェントと人間の貢献者はますます並行して作業を行っています。開発者はレビュー中の機能のためにワークツリーを開いたままにし、一方で1つ以上のエージェントが兄弟ワークツリーの独自のブランチで反復処理を行います。いくつかのプロジェクト選択により、これをよりスムーズに行うことができます。

#### エージェントによる編集にはビルド可能フォルダを使用する {#worktrees-buildable-folders}

エージェントがファイルを追加または削除する場合、`Project.swift`内のファイルリストに依存するものは、プロジェクトが再びビルドされる前に`tuist generate`が必要です。[ビルド可能フォルダ](#buildable-folders)はその責任をXcodeの同期グループに委譲するため、ファイルツリーの編集が再生成をトリガーしなくなります。

これを`generated-projects`<.localized_link href="/guides/features/agentic-coding/skills">スキル</.localized_link>と組み合わせることで、エージェントにTuistプロジェクトの日常のワークフローを教えます。

#### ワークツリーごとにキャッシュを分離しない {#worktrees-shared-cache}

Tuistは<.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link>に従っているため、デフォルトでは同じマシン上のすべてのワークツリーが`~/.cache/tuist`と`~/.local/state/tuist`を共有します。これが望ましい状態です。あるワークツリーでコンパイルされたヘルパー、別のワークツリーでダウンロードされたプラグイン、そして3番目のワークツリーで取得されたモジュールキャッシュのバイナリはすべて再利用可能です。

ワークツリー間での並行した`tuist`呼び出しは、並列実行しても安全です。特に分離が必要な場合を除き、`TUIST_XDG_CACHE_HOME`をワークツリーローカルのパスに向けないでください。そうすると、すべてのワークツリーでヘルパー、プラグイン、バイナリを再度ウォームアップする必要が生じます。

#### ワークツリーごとにSwiftPMのスクラッチ領域を維持する {#worktrees-swiftpm-scratch}

Swift Package Managerには独自のパス制御があります。`--scratch-path`は変更可能な作業状態で、デフォルトは`.build`ですが、`--cache-path`は共有キャッシュディレクトリです。複数のワークツリーがアクティブな場合、これら2つのパスを同じように扱ってはなりません。

Tuistのデフォルトの`tuist install`動作では、SwiftPMのスクラッチ領域がパッケージディレクトリ下に保持されるため、各ワークツリーは独自の`.build`を持ちます。この分離を維持してください。単一の共有SwiftPMスクラッチディレクトリを使用すると、無関係なブランチからのチェックアウト、ビルド中間ファイル、プラグイン、マクロ、およびロックファイルが混在する可能性があります。

`Tuist.swift`内の`installOptions`を通じて、または`tuist install -- ...`を通じてSwiftPM引数を渡す場合、依存関係の取得を高速化したいときは`--cache-path`を共有しますが、`--scratch-path`は未設定のままにするか、ワークツリーローカルのディレクトリを指定してください:

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

Xcode、Swiftツールチェーン、またはプラットフォームによってキャッシュパスを変更する必要がある場合は、ラッパーまたはCI環境変数を使用してください。共有された`--scratch-path`をリポジトリにコミットしないでください。

あるワークツリーでのみ依存関係の状態が破損しているように見える場合は、そのワークツリーの`.build`ディレクトリを削除して`tuist install`を再度実行してください。ワークツリー間で共有されているSwiftPMキャッシュ自体に問題があると思われる場合は、依存関係を再インストールする前に`swift package purge-cache`を使用してください。

#### モジュールキャッシュを活用する {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>こそが、並行ワークツリーの実現を可能にします。Tuistは各ターゲットに対して決定論的な<.localized_link href="/guides/features/projects/hashing">ハッシュ</.localized_link>を計算するため、履歴の大部分を共有するブランチを指す2つのワークツリーは同じバイナリをヒットします。CIから`main`へのすべてのコミットで`tuist cache`を実行し、ローカルでは各ワークツリーでの`tuist generate`がキャッシュから可能なものを取得し、ブランチが実際に変更した部分のみをビルドします。

キャッシュヒットを期待していたのにワークツリーがソースビルドにフォールバックする場合は、<.localized_link href="/guides/features/projects/hashing#debugging">ハッシュのデバッグ手順</.localized_link>に従ってください。非決定論的なハッシュ（通常はプロジェクト内の絶対パスが原因）が最も一般的な原因であり、2つのワークツリーを比較すると顕著に現れます。

#### レジストリを使用してSwift Packageの解決を高速化する {#worktrees-registry}

各ワークツリーはSwiftパッケージを独立して解決します。大規模な依存関係グラフを持つプロジェクトでは、これが急速に累積します。<.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link>に切り替えることで、git履歴の再クローンを回避し、解決時間を数分から数秒に短縮できます。

#### エージェントにプロジェクトのインサイトを提供する {#worktrees-mcp}

多数のワークツリーでビルドとテストが実行されると、エージェントが行える最も有用なことは、*どの*実行が回帰したか、どのテストが不安定か、またはバンドルサイズがどのように変化したかを推論することです。Tuistはそのデータを<.localized_link href="/guides/features/agentic-coding/mcp">MCPサーバー</.localized_link>および<.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link>パッケージを通じて公開しています。ワークフローごとに1つを選択し、それを一貫して使用してください。同じタスクで両方を混在させると、エージェントの動作に一貫性がなくなる傾向があります。
