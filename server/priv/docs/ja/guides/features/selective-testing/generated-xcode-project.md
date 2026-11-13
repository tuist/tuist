---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用し、最新の変更の影響を受けるXcodeおよび生成プロジェクトのテストのみを実行することで、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなるにつれ、すべてのプッシュで全テストを実行するのはスケールしなくなります。Tuistの選択的テストは、Tuistの<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、最後の成功したテスト実行以降に変更があったターゲットのテストのみを実行します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>でテストを選択的に実行するには、`tuist test`コマンドを使用してください。このコマンドは、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>の場合と同様にプロジェクトを<.localized_link href="/guides/features/projects/hashing">ハッシュ化</.localized_link>し、成功時には将来の実行で何が変更されたかを判断するためにハッシュを永続化します。将来の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更されたもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを使用して、テストスイートの実行時のビルド時間を短縮します。選択的テストとモジュールキャッシングを組み合わせることで、CIでのテスト実行時間を大幅に短縮できます。

テスト実行がシミュレータータゲットのみを対象とする場合は、`--destination simulator`を指定して、`tuist test`がキャッシュされたバイナリのシミュレーター用スライスのみを使用およびダウンロードするようにしてください。<.localized_link href="/guides/features/cache/module-cache#destination-selection">デスティネーションの選択</.localized_link>を参照してください。選択的テストのハッシュは、すべての`--destination`値で同じです。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで`tuist test --build-only`を実行すると、Tuistはビルドが出力する製品 alongside に`selective-testing-graph.json`ファイルを永続化できます。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブはどのターゲットを実行するかを判断するためにプロジェクトを再生成したり、Swift Packageの依存関係を解決したりする必要がありません。

Tuistは`--build-only`中にグラフを2か所に書き込みます:

- `-testProductsPath`を指定した場合、`.xctestproducts`バンドル内。
- 派生データの`Build/Products/`ディレクトリ下のすべての`.xctestrun`ファイルの隣。

いずれかの出力をビルド製品 alongside にキャッシュし、テストジョブの`--without-building`に同じパスを渡します。どちらの形式でも動作します:

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

Tuistが入力の隣にそのグラフを見つけられない場合（たとえば、ビルドジョブが`tuist test --build-only`ではなく通常の`xcodebuild build-for-testing`を使用した場合）、影響を受けたターゲットを計算できるようにプロジェクトを再生成するフォールバック処理が行われます。このフォールバックでは、テストジョブでSwift Packageの依存関係が解決されている必要があるため、事前に`tuist install`を実行するか、ジョブ間で`Tuist/.build`をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースにずれが生じると、ハッシュがソースと一致しなくなり、選択的テストによって新しいソースに対して実際には失敗するテストがスキップされる可能性があります。

### どのフラグを使用すべきですか？ {#which-flag-should-i-use}

`.xctestrun`と`.xctestproducts`は2つの異なるXcode出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります:

- **`-testProductsPath` (`.xctestproducts`) — 新しいパイプラインにおすすめ。** これは自己完結型のディレクトリです。ビルドされた`.xctest`バイナリとその`.xctestrun`ファイルが内部に存在し、パスはバンドルルートからの相対パスになるため、どこに移動しても有効性が保たれます。
- **`-xctestrun` (生の`.xctestrun`) — すでに派生データを中心としたパイプラインがある場合に使用してください。** `xcodebuild build-for-testing`はデフォルトで`<derivedData>/Build/Products/`のトップレベルに`.xctestrun`を書き込み、そのツリー内の他の場所にあるテストバンドルを指します。別のジョブで再利用するには、`Build/Products/`内のパスをそのまま維持する必要があります。

新しく始める場合は、`-testProductsPath`を優先してください。すでに派生データをキャッシュしている既存のパイプラインにTuistを組み込む場合、ビルドジョブが`tuist test --build-only`を経由して実行される限り、`-xctestrun`でも同じ高速パスを利用できます。

いずれの入力モードも`-workspace`/`-project`/`-scheme`と排他的であるため、パススルー引数に`-xctestrun`または`-testProductsPath`が含まれている場合、Tuistはそれらのフラグをスキップし、選択されたターゲットを`-only-testing`経由で転送します。

> [!WARNING]
> **モジュール単位 vs ファイル単位の粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能であるため、デフォルトの選択的テストの最大粒度はターゲットレベルです。[カバレッジ戦略](#coverage-based-test-selection)はこれを個々のテストまで絞り込みます。したがって、選択的テストのメリットを最大化するために、ターゲットを小さく焦点を絞った状態に保つことをおすすめします。


## カバレッジベースのテスト選択 {#coverage-based-test-selection}

> [!NOTE]
> **早期アクセス**
>
> カバレッジベースのテスト選択は早期アクセス段階です。アカウントで有効にするにはお問い合わせください。有効になるまで、この戦略はデフォルトの選択的テストと同様に動作します。

デフォルトでは、選択的テストはハッシュがすでに合格したテストターゲット全体をスキップします。`.coverage()`戦略はさらに進んで、残ったテストターゲットの中で、以前の実行でのコードカバレッジが変更の及んだファイルを一つも含まないテストもスキップします。これはXCTestおよびXCUITestテスト、およびそれ用に設定されたスイートの[Swift Testing](#swift-testing)テストで動作します。`Tuist.swift`で有効にしてください:

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

- **カバレッジのアップロード。** Tuistは以前の実行でアップロードされたカバレッジに基づいてテストを選択するため、`tuist test`は`upload: false`で設定された`.coverage()`を含むマニフェストの読み込みに失敗します。
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1以降** [テストターゲットによってリンクされていること](#linking-testcoverageattribution)。これは各テストが実行するファイルを記録し、Tuistが選択しなかったテストをスキップします。これがないターゲットは、デフォルトと同様にターゲット全体がスキップされるだけです。
- **十分な頻度での完全なテスト実行。** `tuist test --no-selective-testing`を使用した実行はすべてのテストを実行し、ベースラインとなります。選択的実行は、同じプラットフォーム上のコミット履歴内の最近の実行と比較し、ベースラインがない場合はカバレッジを適用しません。実行場所と頻度はチームの働き方によりますが、デフォルトブランチのすべてのコミット、毎晩、またはリリースブランチなどが考えられます。デフォルトブランチをおすすめします。そこでの完全な実行は、変更がリリースされる前に、カバレッジでは検知できない要素（テストが依存するフィクスチャやサービスなど）も捕捉します。

戦略が有効な場合、`tuist test`はハッシュがすでに合格したターゲットをスキップし、その後、残りのターゲットのうち変更が影響を与える可能性のあるテストをTuistに問い合わせます。影響を受けるテストがないターゲットはビルドされません。新しいテスト、前回失敗したテスト、変更されたテストファイル内のテスト、および記録されたカバレッジのないテストは常に実行されます。

場合によってはカバレッジが適用されず、その理由が出力に表示されます。ハッシュが合格しなかったターゲットのすべてのテストは、デフォルトの選択的テストと同様に実行されます。これは、同じプラットフォーム上に最近のベースラインがない場合、変更が5,000ファイルを超える場合に発生します。また、`Package.resolved`、`Project.swift`、または`.xcconfig`など、任意のテストに影響を与える可能性のあるファイルが変更された場合にも発生します。すべてのテストを実行するには、`--no-selective-testing`を渡してください。

> [!NOTE]
> **テストカバレッジ**
>
> 単一の実行レポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提とするため、選択的実行のレポートではスキップされたテストが除外されます。Tuistの<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は、代わりに以前の実行からスキップされたテストターゲットのカバレッジを引き継ぎ、各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用します。

### TestCoverageAttributionのリンク {#linking-testcoverageattribution}

パッケージを`Tuist/Package.swift`に追加し、マイナーバージョンに固定してください。0.xのマイナーリリースでは記録内容が変わる可能性があるためです。

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

次に、これをテストターゲットに追加しますが、アプリターゲットには決して追加しないでください。

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Tuistはデフォルトでパッケージを静的フレームワークとしてリンクします。XCTest専用のターゲットはパッケージ内の何も参照しないため、リンカーによって削除され、それに伴って記録とスキップも無効になります。テストターゲットの`OTHER_LDFLAGS`に`-ObjC`を追加するか、`Tuist/Package.swift`でパッケージを動的にリンクしてください。

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testingにはライブラリが参加できる監視APIがないため、そのテストではスイートにTestCoverageAttributionの`.coverageAttribution`トレイトが必要です。このトレイトは、それを持つスイート内にネストされたスイートにも適用されます。これを持たないスイートのテストはテストごとのカバレッジを記録しないため、ターゲットが実行されるたびに実行されます。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **テストが重複しないようにする必要があります。** Swift Testingはデフォルトでプロセス内のテストを並列に実行し、カバレッジカウンターは同時に実行されるテストを区別できないため、これらのテストは独自のカバレッジを記録せず、常に実行されます。`.serialized`はスイート内のテストのみを順序付けるため、ターゲットに単一のスイートしかない場合にのみ有効です。XCTestは何も必要ありません。並列テストは各テストクローンを独自のプロセスで実行します。
- **テストターゲットごとに並列化をオフにします。** Xcodeはこの設定を各テストターゲットに適用するため、テストごとに選択したいターゲットのみでオフにし、スキームの他のターゲットは並列実行を継続できます。別のスキームは不要です。テスト可能なターゲットで設定します：`.testableTarget(target: "CheckoutTests", parallelization: .disabled)`。これにより、そのターゲットのXCTestテストもクローンなしで実行されます。Tuistが生成するスキームはプロジェクトの`testingOptions`からこの設定を取得し、`.parallelizable`または`.swiftTestingOnlyParallelizable`が含まれていない限りオフになります。`tuist test`に`-parallel-testing-enabled YES`または`NO`を渡すと、その実行におけるすべてのターゲットの設定が上書きされます。
- **スキップにはSwift 6.3（Xcode 26.4）以降が必要です。** このトレイトはTuistが選択しなかったテストをキャンセルし、スキップされたものとして報告します。以前のバージョンでは、テストは依然としてカバレッジを記録しますが、Tuistが選択しなかったテストも実行されてしまいます。

### 常に実行されるテスト {#tests-that-always-run}

カバレッジはテストが実行するコードのみを検知します。実際の入力がフィクスチャ、リソース、ネットワーク、または環境であるテストは、カバーされているコードに変更がなくても失敗する可能性があります。それをスキップ不可としてマークすると、Tuistが選択しなくても実行されます。

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

これは実行されるテストターゲット内でのみ適用されます。ハッシュがすでに合格したターゲット、またはTuistがテストを一つも選択しなかったターゲットは全体がスキップされ、開始されないため、そのスキップ不可テストも実行されません。

すべてのオプションについては、[TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests)を参照してください。


## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitフォージの統合が必要**
>
> プル/マージリクエストへの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>をGitフォージと統合してください：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>、または<.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプル/マージリクエストに直接コメントを投稿し、どのテストが実行され、どのテストがスキップされたかを含めます：![GitHubアプリのコメント（Tuist Previewリンク付き）](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミスの調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブを使用して、ハッシュを生成した入力を詳細に確認できます。行を展開すると、コンポーネントごとのサブハッシュ（ソース、依存関係、環境変数、プロジェクトおよびターゲットの設定、Info.plist、エンタイトルメント、ヘッダーなど）が表示され、実行間で変動した入力を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートします。2つの実行間のJSONを比較することは、テストターゲットのハッシュが変動した際にどの入力を変更したかを確認する最速の方法です。
