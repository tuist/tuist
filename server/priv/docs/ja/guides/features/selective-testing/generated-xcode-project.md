---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用して、最新の変更の影響を受けたXcodeおよび生成されたプロジェクトのテストのみを実行し、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 生成された Xcode プロジェクト {#generated-xcode-project}

プロジェクトが大きくなると、プッシュごとにすべてのテストを実行するのはスケーラビリティに欠けます。Tuist の選択的テストは、Tuist の <.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link> に基づき、最後の成功したテスト実行以降に変更されたターゲットを持つテストのみを実行します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link> でテストを選択的に実行するには、`tuist test` コマンドを使用します。このコマンドは、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> と同様の方法でプロジェクトを <.localized_link href="/guides/features/projects/hashing">ハッシュ化</.localized_link> し、成功するとハッシュを永続化して次回の実行での変更箇所を特定します。次回の実行では、`tuist test` がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更されたもののみを実行します。

`tuist test` は <.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを活用して、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシュを組み合わせることで、CI でのテスト実行時間を大幅に削減できます。

テスト実行がシミュレータのみを対象とする場合は、`--destination simulator` を渡して `tuist test` がキャッシュされたバイナリのシミュレータ用スライスのみを使用・ダウンロードするようにしてください。<.localized_link href="/guides/features/cache/module-cache#destination-selection">デスティネーションの選択</.localized_link> を参照してください。選択的テストのハッシュは、すべての `--destination` 値で同じです。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで `tuist test --build-only` を実行し、Tuist がビルド成果物 alongside に `selective-testing-graph.json` ファイルを永続化できるようにします。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブでプロジェクトを再生成したり Swift Package の依存関係を解決したりして実行対象のターゲットを特定する必要がありません。

Tuist は `--build-only` の間にグラフを 2 か所に書き出します。

- `-testProductsPath` を渡した場合、`.xctestproducts` バンドル内に書き出されます。
- Derived Data の `Build/Products/` ディレクトリ下にあるすべての `.xctestrun` ファイルの隣に書き出されます。

いずれかの出力をビルド成果物 alongside にキャッシュし、テストジョブの `--without-building` に同じパスを渡します。どちらの形式でも動作します。

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

Tuist が入力の隣にそのグラフを見つけられない場合（例えば、ビルドジョブで `tuist test --build-only` ではなく通常の `xcodebuild build-for-testing` を使用した場合）、影響を受けたターゲットを計算できるようプロジェクトを再生成するフォールバック処理が行われます。このフォールバックではテストジョブで Swift Package の依存関係が解決されている必要があるため、事前に `tuist install` を実行するか、ジョブ間で `Tuist/.build` をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュがソースと一致しなくなり、選択的テストが新しいソースに対して実際には失敗するはずのテストをスキップしてしまう可能性があります。

### どのフラグを使用すべきですか？ {#which-flag-should-i-use}

`.xctestrun` と `.xctestproducts` は異なる 2 つの Xcode 出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります。

- **`-testProductsPath` (`.xctestproducts`) — 新しいパイプラインにおすすめ。** これは自己完結型のディレクトリです。ビルドされた `.xctest` バイナリとその `.xctestrun` ファイルが内部に格納され、パスはバンドルルートからの相対パスになるため、どこに配置しても有効性が保たれます。
- **`-xctestrun` (生の `.xctestrun`) — Derived Data を中心にした既存のパイプラインがある場合に使用してください。** `xcodebuild build-for-testing` はデフォルトで `<derivedData>/Build/Products/` のトップレベルに `.xctestrun` を書き出し、そのツリー内の他の場所にあるテストバンドルを指します。別のジョブで再利用するには、`Build/Products/` 内のパスを維持する必要があります。

新しく始める場合は、`-testProductsPath` を優先してください。Derived Data をすでにキャッシュしている既存のパイプラインに Tuist を組み込む場合、ビルドジョブが `tuist test --build-only` を経由して実行される限り、`-xctestrun` でも同じ高速な処理が可能です。

いずれの入力モードも `-workspace`/`-project`/`-scheme` と排他的であるため、パススルー引数に `-xctestrun` または `-testProductsPath` が含まれる場合、Tuist はそれらのフラグをスキップし、選択されたターゲットを `-only-testing` を介して転送します。

> [!WARNING]
> **モジュール単位とファイル単位の粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能であるため、デフォルトの選択的テストの最大粒度はターゲット単位です。[カバレッジ戦略](#coverage-based-test-selection) を使用すると、これを個別の XCTest テストまで絞り込むことができます。したがって、選択的テストのメリットを最大化するために、ターゲットを小さく焦点を絞った状態に保つことをおすすめします。


## カバレッジベースのテスト選択 {#coverage-based-test-selection}

> [!NOTE]
> **早期アクセス**
>
> カバレッジベースのテスト選択は早期アクセス段階です。アカウントで有効にするにはお問い合わせください。有効になるまで、この戦略はデフォルトの選択的テストと同様に動作します。

デフォルトでは、選択的テストはハッシュが既に合格しているテストターゲット全体をスキップします。`.coverage()` 戦略はさらに進んで、残ったテストターゲットの中で、以前の実行でのコードカバレッジが変更の影響を受けたファイルを一切含まない XCTest および XCUITest テストもスキップします。`Tuist.swift` で有効にします。

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

- **カバレッジのアップロード。** Tuist は以前の実行でアップロードされたカバレッジに基づいてテストを選択するため、`upload: false` で `.coverage()` を設定したマニフェストを `tuist test` が読み込めません。
- テストターゲットによってリンクされた **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 以降**。これは各テストが実行するファイルを記録し、Tuist が選択しなかったテストをスキップします。これがないターゲットは、デフォルトと同様にターゲット全体としてのみスキップされます。
- **デフォルトブランチでの選択なしのテスト実行。** そのブランチおよびテストをスキップすべきでない他のブランチで `tuist test --no-selective-testing` を実行してください。これらの実行はすべてのテストを実行し、後の実行が比較するためのベースラインとなります。

戦略を有効にすると、`tuist test` はハッシュが既に合格したターゲットをスキップし、残りのターゲットのうち変更の影響を受けるテストを Tuist に問い合わせます。影響を受けるテストがないターゲットはビルドされません。新しいテスト、前回失敗したテスト、変更されたテストファイル内のテスト、記録されたカバレッジのないテストは常に実行されます。Swift Testing のテストは、そのターゲットが実行されるたびに実行されます。

カバレッジで判断できない場合、出力に理由が表示されます。同じプラットフォームでの最近のベースラインがない場合、または変更が5,000ファイルを超える場合、コミットをベースラインとして確立するためにすべてのテストが実行されます。`Package.resolved`、`Project.swift`、あるいは`.xcconfig`など、どのテストにも影響し得るファイルが変更された場合、その実行ではデフォルトの選択的テストが使用されます。すべてのテストを実行するには、`--no-selective-testing`を指定してください。

> [!NOTE]
> **テストカバレッジ**
>
> 単一の実行のレポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提とするため、選択的実行のレポートにはスキップされたテストが含まれません。Tuist の<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は代わりに、各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用して、スキップされたテストターゲットのカバレッジを以前の実行から引き継ぎます。


## プルリクエスト／マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitフォージの統合が必要**
>
> プルリクエスト／マージリクエストへの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>を<.localized_link href="/guides/server/authentication">Gitプラットフォーム</.localized_link>と統合してください。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームに接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプルリクエスト／マージリクエストに直接コメントを投稿し、どのテストが実行され、どのテストがスキップされたかを表示します。![Tuist Previewリンク付きのGitHubアプリコメント](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミスの調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブを使用すると、ハッシュを生成した入力を詳細に確認できます。行を展開すると、ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、エンタイトルメント、ヘッダーなどのコンポーネントごとのサブハッシュが表示され、実行間で変動した入力を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートしてください。2回の実行間でJSONを比較することは、テストターゲットのハッシュが変動した際に変更された入力を確認する最も迅速な方法です。
