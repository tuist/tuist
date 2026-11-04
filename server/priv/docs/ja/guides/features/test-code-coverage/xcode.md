---
{
  "title": "Xcodeのコードカバレッジ",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "XcodeプロジェクトのコードカバレッジをTuistにアップロードし、ファイルごとおよびコミットごとに追跡します。"
}
---
# Xcodeのコードカバレッジ {#xcode-code-coverage}

> [!NOTE] EARLY ACCESS
> Xcodeプロジェクトのコードカバレッジは早期アクセス段階です。アカウントで有効にするには[お問い合わせください](mailto:contact@tuist.dev)。それまで、Tuistは実行からアップロードされたカバレッジを保存しません。

コードカバレッジは、テストがコードのどの行を実行したかを示します。Tuistは各テスト実行の行カバレッジをアップロードし、コミット内の実行をプロジェクト、各ターゲット、各ファイルごとに1つの数値に集約します。ダッシュボードの**コードカバレッジ**ページでは、コミットごとおよび各ブランチの傾向として表示されます。

> [!TIP]
> Tuistでプロジェクトを生成している場合は、代わりに<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成済みプロジェクトガイド</.localized_link>に従ってください。これはバイナリキャッシュ由来のコードを測定し、選択的テストでスキップされたテストターゲットのカバレッジを引き継ぎます。

## セットアップ {#setup}

### カバレッジの収集 {#collect-coverage}

`Tuist.swift`でカバレッジのアップロードを有効にしてください。デフォルトでは無効になっています:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD`環境変数(`1`または`0`)はオプションよりも優先され、例えばフォークからのプルリクエストを実行するジョブでアップロードを無効にする場合に使用します。

その後、スキームのテストアクション(**スキームを編集 › テスト › オプション**)で**コードカバレッジ**を有効にするか、実行時に`-enableCodeCoverage YES`を渡し、`tuist xcodebuild test`を通じてテストを実行します:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuistは、実行で収集されたカバレッジをテスト結果とともにアップロードします。

### CIで各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは多くの場合、複数のジョブ(スキームごと、シャードごと、プラットフォームごと)から得られます。Tuistは最後に報告されたジョブを自動検出できないため、明示的に通知する必要があります。コミットのすべてのテストジョブが終了したら、それらすべてに依存するジョブで次を実行します:

```sh
tuist coverage complete
```

コミットが完了するまで、そのカバレッジは**進行中**として表示され、ブランチの傾向からは除外されます。各ステータスの詳細は<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成済みプロジェクトガイド</.localized_link>に記載されています。

## スキップされたテスト {#skipped-tests}

実行が`-skip-testing`でテストをスキップすると、コミットのテストがカバーする範囲よりも少ない測定となり、Tuistは以前の執行からそれらのテストを引き継ぐことができません。コミットのカバレッジは、そのコミットで別の実行がそれらを実行しない限り、**不完全**となります。コミットを完全な状態に保つには、コミットごとに少なくとも1回の実行ですべてのテストを実行してください。

検疫でスキップされるテストはカバレッジに含まれないため、コミットを**不完全**にすることはありません。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集にはオーバーヘッドが生じ、主にテスト終了後、Xcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートする間に発生します。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。

## カバレッジのクエリ {#querying}

`tuist coverage`コマンドは、ダッシュボードに表示されるデータを読み取ります。`--commit`を指定しない場合、`--branch`の最新完了コミット、またはデフォルトブランチの最新完了コミットのデータを読み取ります:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

いずれのコマンドもスクリプト用途で`--json`を受け付けます。
