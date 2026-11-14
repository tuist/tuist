---
{
  "title": "Xcode コードカバレッジ",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "Xcode プロジェクトのコードカバレッジを Tuist にアップロードし、ファイルごとおよびコミットごとに追跡します。"
}
---
# Xcodeのコードカバレッジ {#xcode-code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuistは各テスト実行の行カバレッジをアップロードし、プロジェクト、各ターゲット、各ファイルについて、コミット内の複数の実行を1つの数値に集約します。ダッシュボードの**Code Coverage**ページでは、コミットごとの値とブランチごとの推移を確認できます。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Tuistでプロジェクトを生成している場合は、代わりに<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">generated project guide</.localized_link>を参照してください。バイナリキャッシュから取得したコードも測定対象となり、選択的テストでスキップされたテストターゲットのカバレッジを引き継ぎます。

## セットアップ {#setup}

### カバレッジの収集 {#collect-coverage}

`Tuist.swift`でカバレッジのアップロードを有効にしてください。デフォルトでは無効になっています：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD`環境変数（`1`または`0`）はオプションよりも優先され、例えばフォークからのプルリクエストを実行するジョブでアップロードを無効にする場合に使用します。

次に、スキームのテストアクション（**Edit Scheme › Test › Options**）で**Code Coverage**を有効にするか、実行時に`-enableCodeCoverage YES`を指定し、`tuist xcodebuild test`を通じてテストを実行します：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuistは、実行中に収集したカバレッジをテスト結果とともにアップロードします。

### CIで各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、スキーム、シャード、プラットフォームごとに分かれた複数のジョブから得られることがよくあります。Tuistは最後のジョブが報告を終えたタイミングを自動で検出できないため、明示的に通知する必要があります。コミットに関連するすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行します：

```sh
tuist coverage complete
```

コミットが完了するまで、そのカバレッジは**In progress**として表示され、ブランチの推移には反映されません。各ステータスの詳細は<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">generated project guide</.localized_link>に記載されています。

## スキップされたテスト {#skipped-tests}

実行時に`-skip-testing`を使用してテストをスキップすると、コミットのテストがカバーする範囲より少ない測定となり、Tuistは以前の実行からそれらのテストの結果を引き継ぐことができません。そのコミットでの別の実行でそれらが実行されていない限り、コミットのカバレッジは**Incomplete**となります。コミットを完了状態に保つには、コミットごとに少なくとも1回の実行ですべてのテストを実行してください。

隔離によってスキップされたテストはカバレッジの対象外であるため、コミットが**Incomplete**になることはありません。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集にはオーバーヘッドが発生しますが、主にテスト終了後、Xcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートする間に生じます。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。

## カバレッジのクエリ {#querying}

`tuist coverage`コマンドは、ダッシュボードに表示されるデータを読み取ります。`--commit`を指定しない場合、`--branch`またはデフォルトブランチの最新の完了したコミットのデータを読み取ります：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

いずれのコマンドも、スクリプト用途で`--json`を受け付けます。
