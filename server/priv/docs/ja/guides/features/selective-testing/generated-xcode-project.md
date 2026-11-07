---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用して、最新の変更の影響を受けたXcodeおよび生成されたプロジェクトのテストのみを実行し、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなるにつれて、すべてのプッシュで全テストを実行するのはスケーラビリティに欠けます。Tuistの選択的テストは、Tuistの<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、最後の成功したテスト実行以降に変更があったターゲットに関連するテストのみを実行します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>でテストを選択的に実行するには、`tuist test`コマンドを使用してください。このコマンドは、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>の場合と同様にプロジェクトを<.localized_link href="/guides/features/projects/hashing">ハッシュ化</.localized_link>し、成功するとそのハッシュを保存して、次回の実行で何が変わったかを判断します。次回の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更があったもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを使用して、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシングを組み合わせることで、CIでのテスト実行時間を大幅に削減できます。

テスト実行がシミュレータのみを対象とする場合は、`--destination simulator`を渡して、`tuist test`がキャッシュされたバイナリのシミュレータ用スライスのみを使用・ダウンロードするようにしてください。<.localized_link href="/guides/features/cache/module-cache#destination-selection">宛先選択</.localized_link>をご覧ください。選択的テストのハッシュは、すべての`--destination`値で同じです。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで`tuist test --build-only`を実行すると、Tuistはビルドが出力する製品 alongside に`selective-testing-graph.json`ファイルを永続化できます。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブでプロジェクトを再生成したり、Swift Packageの依存関係を解決して実行対象のターゲットを特定したりする必要がありません。

Tuistは`--build-only`中にグラフを2箇所に書き出します。

- `-testProductsPath`を渡した場合、`.xctestproducts`バンドル内に書き出されます。
- 派生データの`Build/Products/`ディレクトリ下にあるすべての`.xctestrun`ファイルの隣に書き出されます。

いずれかの出力をビルド製品と一緒にキャッシュし、テストジョブで`--without-building`に同じパスを指定してください。どちらの形式でも動作します。

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

Tuistが入力の隣にそのグラフを見つけられない場合（例えば、ビルドジョブで`tuist test --build-only`ではなく通常の`xcodebuild build-for-testing`を使用した場合）、影響を受けるターゲットを計算できるようにプロジェクトを再生成するフォールバック処理が行われます。このフォールバックでは、テストジョブでSwift Packageの依存関係が解決されている必要があるため、事前に`tuist install`を実行するか、ジョブ間で`Tuist/.build`をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュがソースと一致しなくなり、選択的テストが新しいソースに対して実際には失敗するテストをスキップしてしまう可能性があります。

### どのフラグを使うべきですか？ {#which-flag-should-i-use}

`.xctestrun`と`.xctestproducts`は異なる2つのXcode出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります。

- **`-testProductsPath`（`.xctestproducts`）— 新しいパイプラインにおすすめ。** これは自己完結型ディレクトリです。ビルドされた`.xctest`バイナリとその`.xctestrun`ファイルが内部に格納され、パスはバンドルルートからの相対パスになるため、どこに移動しても有効性が保たれます。
- **`-xctestrun`（生の`.xctestrun`）— すでに派生データを中心としたパイプラインがある場合に使用。** `xcodebuild build-for-testing`はデフォルトで`<derivedData>/Build/Products/`のトップレベルに`.xctestrun`を書き出し、そのツリー内の他の場所にあるテストバンドルを指し示します。別のジョブで再利用するには、`Build/Products/`内のパスをそのまま維持する必要があります。

新しく始める場合は、`-testProductsPath`を優先してください。すでに派生データをキャッシュしている既存のパイプラインにTuistを組み込む場合でも、ビルドジョブが`tuist test --build-only`を通じて実行される限り、`-xctestrun`で同じ高速パスを利用できます。

いずれの入力モードも`-workspace`/`-project`/`-scheme`とは排他的であるため、パススルー引数に`-xctestrun`または`-testProductsPath`が含まれる場合、Tuistはそれらのフラグをスキップし、選択されたターゲットを`-only-testing`経由で転送します。

> [!WARNING]
> **モジュール単位 vs ファイル単位の粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能であるため、デフォルトの選択的テストの最大粒度はターゲット単位です。[カバレッジ戦略](#coverage-based-test-selection)を使用すると、これを単一のXCTestテストまで絞り込むことができます。したがって、選択的テストのメリットを最大化するために、ターゲットを小さく焦点を絞った状態に保つことをおすすめします。


## カバレッジベースのテスト選択 {#coverage-based-test-selection}

> [!NOTE]
> **早期アクセス**
>
> カバレッジベースのテスト選択は早期アクセス段階です。アカウントで有効にするにはお問い合わせください。有効になるまでは、この戦略はデフォルトの選択的テストと同様に動作します。

デフォルトでは、選択的テストはハッシュが既に合格済みのテストターゲット全体をスキップします。`.coverage()`戦略はさらに進んで、残ったテストターゲットの中で、以前の実行でのコードカバレッジが変更の影響を受けたファイルを一切含まないXCTestおよびXCUITestテストもスキップします。`Tuist.swift`で有効にしてください。

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

この戦略には以下が必要です。

- **カバレッジのアップロード。** Tuistは以前の実行でアップロードされたカバレッジに基づいてテストを選択するため、`tuist test`は`upload: false`で設定された`.coverage()`を含むマニフェストの読み込みに失敗します。
- テストターゲットによってリンクされた **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0以降**。これは各テストが実行するファイルを記録し、Tuistが選択しなかったテストをスキップします。これを持たないターゲットは、デフォルトと同様にターゲット全体としてのみスキップされます。
- **デフォルトブランチでの選択なしのテスト実行。** そのブランチ、およびテストをスキップすべきではない他のあらゆるブランチで`tuist test --no-selective-testing`を実行してください。これらの実行はすべてのテストを実行し、後続の実行が比較するためのベースラインとなります。

戦略が有効な場合、`tuist test`はハッシュが既に合格済みのターゲットをスキップし、その後、残りのターゲットのうち変更が影響を与える可能性のあるテストをTuistに問い合わせます。影響を受けるテストがないターゲットはビルドされません。新しいテスト、前回失敗したテスト、変更されたテストファイル内のテスト、および記録されたカバレッジのないテストは常に実行されます。Swift Testingのテストは、そのターゲットが実行されるたびに実行されます。

場合によってはカバレッジが適用されず、出力にその理由が表示されます。ハッシュが合格しなかったターゲットのすべてのテストが、デフォルトの選択的テストと同様に実行されます。これは、同じプラットフォームでの最近のベースラインがない場合、変更が5,000ファイルを超える場合、または`Package.resolved`、`Project.swift`、`.xcconfig`など、どのテストにも影響を与える可能性のあるファイルが変更された場合に発生します。すべてのテストを実行するには、`--no-selective-testing`を渡してください。

> [!NOTE]
> **テストカバレッジ**
>
> 単一の実行のレポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提としているため、選択的実行のレポートではスキップされたテストが除外されます。Tuistの<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は代わりに、各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用して、以前の実行からスキップされたテストターゲットのカバレッジを引き継ぎます。


## プルリクエスト/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitフォージの統合が必要**
>
> プルリクエスト/マージリクエストへの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>を<.localized_link href="/guides/server/authentication">Gitプラットフォーム</.localized_link>と統合してください。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームに接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプルリクエスト/マージリクエストに直接コメントを投稿し、どのテストが実行され、どのテストがスキップされたかを表示します。![Tuist Previewリンク付きのGitHubアプリコメント](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミスの調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブを使用すると、ハッシュを生成した入力項目を詳細に確認できます。行を展開すると、ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、エンタイトルメント、ヘッダーなどのコンポーネントごとのサブハッシュが表示され、実行間で変動した入力項目を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートします。2回の実行間でJSONを比較することは、テストターゲットのハッシュが変動した際にどの入力が変更されたかを確認する最も迅速な方法です。
