---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 選択的テスト · 機能 · ガイド · Tuist",
  "description": "Tuistの選択的テストを使用すると、最新の変更の影響を受けたXcodeおよび生成されたプロジェクトのテストのみを実行できるため、継続的インテグレーションは数秒でフィードバックを提供します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

プロジェクトが大きくなると、プッシュごとにすべてのテストを実行するのはスケーラビリティに限界が生じます。Tuistの<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>に基づき、選択的テストでは、最後の成功したテスト実行以降に変更があったターゲットに関連するテストのみを実行します。

<.localized_link href="/guides/features/projects">生成されたプロジェクト</.localized_link>で選択的にテストを実行するには、`tuist test`コマンドを使用します。このコマンドは、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>の場合と同様にプロジェクトを<.localized_link href="/guides/features/projects/hashing">ハッシュ化</.localized_link>し、成功するとそのハッシュを永続化して、将来の実行で何が変更されたかを判断します。将来の実行では、`tuist test`がハッシュを透過的に使用してテストを絞り込み、最後の成功したテスト実行以降に変更があったもののみを実行します。

`tuist test`は<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>と直接統合され、ローカルまたはリモートストレージから可能な限り多くのバイナリを使用して、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシングを組み合わせることで、CIでのテスト実行時間を大幅に削減できます。

テスト実行がシミュレータのみを対象とする場合は、`--destination simulator`を指定して、`tuist test`がキャッシュされたバイナリのシミュレータ用スライスのみを使用およびダウンロードするようにします。<.localized_link href="/guides/features/cache/module-cache#destination-selection">宛先選択</.localized_link>をご覧ください。選択的テストのハッシュは、すべての`--destination`値で同じです。

## ビルドジョブとテストジョブの分離 {#separate-build-and-test-jobs}

選択的テストは、ビルドジョブとテストジョブの分離をサポートしています。ビルドジョブで`tuist test --build-only`を実行し、Tuistがビルド成果物 alongside `selective-testing-graph.json`ファイルを永続化できるようにします。このグラフには選択的テストに必要なハッシュが含まれているため、テストジョブでプロジェクトを再生成したり、Swift Packageの依存関係を解決して実行対象のターゲットを特定したりする必要がありません。

Tuistは`--build-only`中にグラフを2箇所に書き出します。

- `-testProductsPath`を指定した場合、`.xctestproducts`バンドル内に書き出されます。
- Derived Dataの`Build/Products/`ディレクトリ下にある各`.xctestrun`ファイルの隣に書き出されます。

いずれかの出力をビルド成果物 alongside キャッシュし、テストジョブの`--without-building`に同じパスを指定します。どちらの形式でも動作します。

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

Tuistが入力 alongside そのグラフを見つけられない場合（例えば、ビルドジョブが`tuist test --build-only`ではなく通常の`xcodebuild build-for-testing`を使用した場合）、影響を受けるターゲットを計算できるようにプロジェクトを再生成するフォールバック処理が行われます。このフォールバック処理では、テストジョブでSwift Packageの依存関係が解決されている必要があるため、事前に`tuist install`を実行するか、ジョブ間で`Tuist/.build`をキャッシュしてください。

グラフはビルド時点のソースツリーを反映しています。テストジョブはビルドジョブと同じコミットに対して実行してください。両者の間でソースに変更が生じると、ハッシュがソースと一致しなくなり、選択的テストが新しいソースでは実際に失敗するはずのテストをスキップしてしまう可能性があります。

### どのフラグを使用すべきですか？ {#which-flag-should-i-use}

`.xctestrun`と`.xctestproducts`は2種類の異なるXcode出力形式であり、ポータビリティとパイプラインの利便性のトレードオフがあります。

- **`-testProductsPath` (`.xctestproducts`) — 新しいパイプラインにおすすめ。** これは自己完結型のディレクトリです。ビルドされた`.xctest`バイナリとその`.xctestrun`ファイルが内部に存在し、パスはバンドルルートからの相対パスとなるため、どこに移動しても有効性が保たれます。
- **`-xctestrun` (生の`.xctestrun`) — Derived Dataを中心に構築された既存のパイプラインがある場合に使用。** `xcodebuild build-for-testing`はデフォルトで`<derivedData>/Build/Products/`のトップレベルに`.xctestrun`を書き出し、そのツリー内の他の場所にあるテストバンドルを指し示します。別のジョブで再利用するには、`Build/Products/`内のパスをそのまま維持する必要があります。

新しく始める場合は、`-testProductsPath`を選択してください。Derived Dataをすでにキャッシュしている既存のパイプラインにTuistを組み込む場合、ビルドジョブが`tuist test --build-only`を経由して実行される限り、`-xctestrun`でも同じ高速な処理が可能になります。

いずれの入力モードも`-workspace`/`-project`/`-scheme`と排他的であるため、パススルー引数に`-xctestrun`または`-testProductsPath`が含まれる場合、Tuistはそれらのフラグをスキップし、選択されたターゲットを`-only-testing`経由で転送します。

> [!WARNING]
> **モジュール粒度 vs ファイル粒度**
>
> テストとソース間のコード内依存関係を検出することが不可能なため、デフォルトの選択的テストの最大粒度はターゲットレベルです。[カバレッジ戦略](#coverage-based-test-selection)を用いることで、これを個別のテストまで絞り込むことができます。したがって、選択的テストのメリットを最大化するために、ターゲットを小さく焦点を絞った状態に保つことをおすすめします。


## カバレッジベースのテスト選択 {#coverage-based-test-selection}

> [!NOTE]
> **早期アクセス**
>
> カバレッジベースのテスト選択は早期アクセス機能です。アカウントで有効にするにはお問い合わせください。有効になるまで、この戦略はデフォルトの選択的テストと同様に動作します。

デフォルトでは、選択的テストはハッシュが既に合格済みのテストターゲット全体をスキップします。`.coverage()`戦略はさらに進んで、残ったテストターゲットの中で、以前の実行でのコードカバレッジが変更の影響を受けたファイルを全く含まないテストもスキップします。これはXCTestおよびXCUITestテスト、およびそれ用に設定されたスイート内の[Swift Testing](#swift-testing)テストで動作します。`Tuist.swift`で有効にします。

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

- **カバレッジのアップロード。** Tuistは以前の実行でアップロードされたカバレッジに基づいてテストを選択するため、`upload: false`で`.coverage()`を設定したマニフェストを`tuist test`が読み込めないと失敗します。
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1以降** が[テストターゲットによってリンクされていること](#linking-testcoverageattribution)。これは各テストが実行するファイルを記録し、Tuistが選択しなかったテストをスキップします。これがないターゲットは、デフォルトと同様にターゲット全体としてのみスキップされます。
- **十分な頻度での完全なテスト実行。** `tuist test --no-selective-testing`を使用した実行はすべてのテストを実行し、ベースラインとなります。選択的実行は、同じプラットフォーム上のコミット履歴内の最近の実行と比較し、ベースラインがない場合はカバレッジを適用しません。実行場所と頻度はチームのワークフローによります。デフォルトブランチのすべてのコミット、毎夜、またはリリースブランチなどです。デフォルトブランチをおすすめします。そこでの完全な実行により、変更がリリースされる前に、カバレッジでは検出できない要素（テストが依存するフィクスチャやサービスなど）も捕捉できます。

戦略が有効な場合、`tuist test`はハッシュが既に合格済みのターゲットをスキップし、その後、残りのターゲットのうち変更が影響し得るテストをTuistに問い合わせます。影響を受けるテストがないターゲットはビルドされません。新しいテスト、前回失敗したテスト、変更されたテストファイル内のテスト、および記録されたカバレッジがないテストは常に実行されます。

場合によってはカバレッジが適用されず、その理由が出力に表示されます。ハッシュが合格しなかったターゲットのすべてのテストが、デフォルトの選択的テストと同様に実行されます。これは、同じプラットフォーム上に最近のベースラインがない場合、変更が5,000ファイル以上に関与した場合、または`Package.resolved`、`Project.swift`、`.xcconfig`など、どのテストにも影響し得るファイルが変更された場合に発生します。すべてのテストを実行するには、`--no-selective-testing`を指定してください。

> [!NOTE]
> **テストカバレッジ**
>
> 単一の実行レポートを読み取るカバレッジツール（Xcodeのものを含む）は、テストスイート全体が実行されたことを前提とするため、選択的実行のレポートではスキップされたテストが除外されます。Tuistの<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">コードカバレッジ</.localized_link>は、代わりに各実行で記録する<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">ターゲットレベルのカバレッジ</.localized_link>を使用して、スキップされたテストターゲットのカバレッジを以前の実行から引き継ぎます。

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

Tuistはデフォルトでパッケージを静的フレームワークとしてリンクします。XCTest専用のターゲットはパッケージ内の何も参照しないため、リンカーはそれを削除し、記録とスキップも一緒に行われません。テストターゲットの`OTHER_LDFLAGS`に`-ObjC`を追加するか、`Tuist/Package.swift`でパッケージを動的にリンクしてください。

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testingにはライブラリが参加できる観測APIがないため、そのテストではスイートにTestCoverageAttributionの`.coverageAttribution`トレイトが必要です。このトレイトは、それを持つスイート内にネストされたスイートにも適用されます。これを持たないスイートのテストはテストごとのカバレッジを記録しないため、ターゲットが実行されるたびに実行されます。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **テストが重複してはいけません。** Swift Testingはデフォルトでプロセス内のテストを並列に実行し、カバレッジカウンターは同時に実行されるテストを区別できないため、それらのテストは独自のカバレッジを記録せず、常に実行されます。`.serialized`はスイート自身のテストのみを順序付けるため、ターゲットに単一のスイートしかない場合にのみ十分です。XCTestは何も必要ありません。並列テストは各テストクローンを独自のプロセスで実行します。
- **テストターゲットごとに並列化をオフにする。** Xcodeはこの設定を各テストターゲットに適用するため、テストごとに選択したいターゲットのみでオフにし、スキームの他のターゲットは並列実行を継続できます。別のスキームは不要です。テスト可能ターゲットで設定します：`.testableTarget(target: "CheckoutTests", parallelization: .disabled)`。これにより、そのターゲットのXCTestテストもクローンなしで実行されます。Tuistが生成するスキームはプロジェクトの`testingOptions`からこれを取得し、`.parallelizable`または`.swiftTestingOnlyParallelizable`が含まれていない限りオフになります。`tuist test`に`-parallel-testing-enabled YES`または`NO`を渡すと、その実行においてすべてのターゲットの設定が上書きされます。
- **スキップにはSwift 6.3（Xcode 26.4）以降が必要です。** このトレイトは、Tuistが選択しなかったテストをキャンセルし、スキップされたものとして報告します。それ以前のバージョンでは、テストは依然としてカバレッジを記録しますが、Tuistが選択しなかったテストも実行されてしまいます。

### 常に実行されるテスト {#tests-that-always-run}

カバレッジはテストが実行するコードのみを検出します。実際の入力がフィクスチャ、リソース、ネットワーク、または環境であるテストは、カバーされたコードに変更がなくても失敗する可能性があります。それをスキップ不可としてマークすると、Tuistが選択しなくても実行されます。

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

これは実行されるテストターゲット内でのみ適用されます。ハッシュが既に合格したターゲット、またはTuistがテストを一つも選択しなかったターゲットは全体としてスキップされ、開始されないため、そのスキップ不可テストも実行されません。

すべてのオプションについては、[TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests)を参照してください。

### 選択内容の検査 {#inspecting-a-selection}

テスト実行の「選択的テスト」タブには、カバレッジによって何が選択され、その理由が表示されます。同じデータはCLIからも利用でき、スクリプト用に`--json`を使用でき、エージェントには<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocolサーバー</.localized_link>を通じてアクセスできます。

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

カバレッジが適用されない場合でも、テストはカバレッジベースの選択としてカウントされます。その理由は、カバレッジが判断できなかった理由を示します（例：`tracked_file_changed`）。


## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Gitフォージの統合が必要**
>
> プル/マージリクエストの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuistプロジェクト</.localized_link>をGitフォージと統合してください：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>、または<.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと接続され、CIワークフローの一部として`tuist test`の使用を開始すると、Tuistはプル/マージリクエストに直接コメントを投稿します。これには、実行されたテストとスキップされたテストが含まれます：![GitHubアプリのコメント（Tuist Previewリンク付き）](/images/guides/features/selective-testing/github-app-comment.png)


## ダッシュボードでのミスの調査 {#investigating-misses-on-the-dashboard}

以前キャッシュされていたテストターゲットがミスとして表示された場合、テスト実行ページの**選択的テスト**タブを使用すると、ハッシュを生成した入力を詳しく調べることができます。行を展開すると、コンポーネントごとのサブハッシュ（ソース、依存関係、環境変数、プロジェクトおよびターゲット設定、Info.plist、エンタイトルメント、ヘッダーなど）が表示され、実行間で変動した入力を特定できます。

選択的テストカードの上部にある**JSONとしてコピー**ボタンを使用して、すべての選択的テストターゲットとそのハッシュ、サブハッシュをエクスポートします。2つの実行間でJSONを比較することは、テストターゲットのハッシュが変動した際に変更された入力を確認する最も迅速な方法です。
