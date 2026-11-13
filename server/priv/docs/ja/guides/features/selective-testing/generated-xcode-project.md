---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用すると、最新の変更の影響を受けたXcodeおよび生成プロジェクトのテストのみを実行できるため、継続的インテグレーションは数秒でフィードバックを返します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなると、プッシュごとにすべてのテストを実行するのはスケーラビリティに欠けます。Tuistの選択的テストは、Tuistの<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、最後の成功したテスト実行以降に変更があったターゲットに関連するテストのみを実行します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>で選択的にテストを実行するには、`tuist test`コマンドを使用してください。このコマンドは、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と同様の方法でプロジェクトを<.localized_link href="/guides/features/projects/hashing">ハッシュ化</.localized_link>し、成功するとハッシュを永続化して次回の実行時に変更点を判定します。次回以降の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更があったもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージからバイナリを可能な限り活用して、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシュを組み合わせることで、CIでのテスト実行時間を大幅に削減できます。

テスト実行がシミュレータのみを対象とする場合は、`--destination simulator`を指定して、`tuist test`がキャッシュ済みバイナリのシミュレータ用スライスのみを使用・ダウンロードするようにしてください。<.localized_link href="/guides/features/cache/module-cache#destination-selection">デスティネーションの選択</.localized_link>を参照してください。選択的テストのハッシュは、すべての`--destination`値で同じです。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで`tuist test --build-only`を実行すると、Tuistはビルドが出力する製品 alongside に`selective-testing-graph.json`ファイルを永続化できます。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブ側でプロジェクトを再生成したりSwift Packageの依存関係を解決したりして、実行対象のターゲットを特定する必要がありません。

Tuistは`--build-only`中にグラフを2か所に書き出します:

- `-testProductsPath`を指定した場合、`.xctestproducts`バンドル内に書き出されます。
- 派生データの`Build/Products/`ディレクトリ下にある各`.xctestrun`ファイルの隣に書き出されます。

いずれかの出力をビルド製品 alongside にキャッシュし、テストジョブで`--without-building`に同じパスを渡してください。どちらの形式でも動作します:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuistが入力の隣にそのグラフを見つけられない場合(たとえば、ビルドジョブで`tuist test --build-only`ではなく通常の`xcodebuild build-for-testing`を使用した場合)、影響を受けるターゲットを計算できるようプロジェクトの再生成にフォールバックします。このフォールバックではテストジョブでSwift Packageの依存関係が解決されている必要があるため、事前に`tuist install`を実行するか、ジョブ間で`Tuist/.build`をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュがソースと一致しなくなり、選択的テストが新しいソースでは実際に失敗するテストをスキップしてしまう可能性があります。

### どのフラグを使うべきか? {#which-flag-should-i-use}

`.xctestrun`と`.xctestproducts`は異なる2つのXcode出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります:

- **`-testProductsPath` (`.xctestproducts`) — 新しいパイプラインにおすすめ。** 自己完結型のディレクトリです。ビルド済みの`.xctest`バイナリとその`.xctestrun`ファイルがバンドルルートからの相対パスで格納されるため、どこに配置しても有効性が保たれます。
- **`-xctestrun` (生の`.xctestrun`) — 派生データを中心とした既存のパイプラインがある場合に使用。**`xcodebuild build-for-testing`はデフォルトで`<derivedData>/Build/Products/`のトップレベルに`.xctestrun`を書き出し、そのツリー内の他の場所にあるテストバンドルを指します。別のジョブで再利用するには、`Build/Products/`内のパスをそのまま維持する必要があります。

新規で始める場合は、`-testProductsPath`を選択してください。派生データをすでにキャッシュしている既存のパイプラインにTuistを組み込む場合でも、ビルドジョブが`tuist test --build-only`を経由していれば、`-xctestrun`で同じ高速パスを利用できます。

どちらの入力モードも`-workspace`/`-project`/`-scheme`とは排他的であるため、パススルー引数に`-xctestrun`または`-testProductsPath`が含まれる場合、Tuistはそれらのフラグをスキップし、選択されたターゲットを`-only-testing`経由で転送します。

> [!WARNING]
> **モジュール粒度とファイル粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能なため、デフォルトの選択的テストの最大粒度はターゲットレベルです。[カバレッジ戦略](#coverage-based-test-selection)を用いると、個々のXCTestテスト単位まで絞り込めます。したがって、選択的テストのメリットを最大化するため、ターゲットは小さく焦点を絞った状態に保つことをおすすめします。


## カバレッジベースのテスト選択 {#coverage-based-test-selection}

> [!NOTE]
> **早期アクセス**
>
> カバレッジベースのテスト選択は早期アクセス段階です。アカウントで有効にするにはお問い合わせください。有効になるまでは、この戦略はデフォルトの選択的テストと同様に動作します。

デフォルトでは、選択的テストはハッシュがすでに合格したテストターゲット全体をスキップします。`.coverage()`戦略はさらに進んで、残ったテストターゲットのうち、以前の実行でのコードカバレッジが変更の触れたファイルを一切含まないXCTestおよびXCUITestテストもスキップします。`Tuist.swift`で有効にしてください:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

この戦略には以下が必要です:

- **カバレッジのアップロード。** Tuistは以前の実行でアップロードされたカバレッジに基づいてテストを選択するため、`tuist test`は`upload: false`で`.coverage()`を設定したマニフェストの読み込みで失敗します。
- **テストターゲットによってリンクされた[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0以降**。これは各テストが実行するファイルを記録し、Tuistが選択しなかったテストをスキップします。これがないターゲットは、デフォルトと同様、ターゲット全体としてのみスキップされます。
- **デフォルトブランチでの選択なしのテスト実行。** そこおよびテストをスキップすべきでない他のブランチで`tuist test --no-selective-testing`を実行してください。これらの実行はすべてのテストを実行し、後の実行が比較するためのベースラインとなります。

戦略が有効な場合、`tuist test`はハッシュがすでに合格したターゲットをスキップし、その後、残りのターゲットのうち変更が影響し得るテストをTuistに問い合わせます。影響を受けるテストがないターゲットはビルドされません。新しいテスト、前回失敗したテスト、変更されたテストファイル内のテスト、および記録されたカバレッジのないテストは常に実行されます。Swift Testingのテストは、そのターゲットが実行されるたびに実行されます。

場合によってはカバレッジが適用されず、出力にその理由が表示されます。ハッシュが合格しなかったターゲットのすべてのテストが、デフォルトの選択的テストと同様に実行されます。これは、同じプラットフォームでの最近のベースラインがない場合、変更が5,000ファイルを超える場合、あるいは`Package.resolved`、`Project.swift`、`.xcconfig`など、あらゆるテストに影響し得るファイルが変更された場合に発生します。すべてのテストを実行するには、`--no-selective-testing`を指定してください。

> [!NOTE]
> **テストカバレッジ**
>
> 単一の実行のレポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提とするため、選択的実行のレポートにはスキップされたテストが含まれません。代わりに、Tuistの<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は、各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用して、以前の実行からスキップされたテストターゲットのカバレッジを引き継ぎます。


## プルリクエスト/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitフォージの統合が必要**
>
> プルリクエスト/マージリクエストへの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>をGitフォージと統合してください：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>、または<.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームに接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプルリクエスト/マージリクエストに直接コメントを投稿します。これには、どのテストが実行され、どのテストがスキップされたかが含まれます。![Tuist Previewリンク付きのGitHubアプリコメント](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミスの調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブを使用すると、ハッシュを生成した入力を詳しく調べることができます。行を展開すると、ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、エンタイトルメント、ヘッダーなどのコンポーネントごとのサブハッシュが表示され、実行間で変動した入力を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートします。2つの実行間でJSONを比較することは、テストターゲットのハッシュが変動した際にどの入力に変更があったかを確認する最も迅速な方法です。
