---
{
  "title": "Xcode コードカバレッジ",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "Xcode プロジェクトのコードカバレッジを Tuist にアップロードし、ファイルごとおよびコミットごとに追跡します。"
}
---
# Xcodeのコードカバレッジ {#xcode-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

コードカバレッジは、テストが実行したコードの行を示します。Tuistは各テスト実行の行カバレッジをアップロードし、コミット内のすべての実行を集約して、プロジェクト全体、各ターゲット、および各ファイルごとに1つの数値としてまとめます。ダッシュボードの**コードカバレッジ**ページでは、コミットごとの値と各ブランチのトレンドを表示します。

> [!TIP]
> Tuistでプロジェクトを生成している場合は、代わりに<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成されたプロジェクトのガイド</.localized_link>に従ってください。このガイドでは、バイナリキャッシュから提供されるコードを測定し、選択的テストでスキップされたテストターゲットのカバレッジを引き継ぐ方法について説明しています。

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

次に、スキームのテストアクション（**Edit Scheme › Test › Options**）で**コードカバレッジ**を有効にするか、実行時に`-enableCodeCoverage YES`を渡し、`tuist xcodebuild test`を通じてテストを実行します：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuistは、テスト結果とともに実行中に収集されたカバレッジをアップロードします。

### CIで各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、複数のジョブ（スキームごと、シャードごと、またはプラットフォームごと）から得られることがよくあります。Tuistは最後に報告されたジョブを自動で検出できないため、明示的に通知する必要があります。コミットに関連するすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行します：

```sh
tuist coverage complete
```

コミットが完了するまで、そのカバレッジは**進行中**として表示され、ブランチのトレンドには含まれません。各ステータスの詳細については、<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成されたプロジェクトのガイド</.localized_link>をご覧ください。

## スキップされたテスト {#skipped-tests}

実行時に`-skip-testing`を使用してテストをスキップすると、コミットのテストがカバーする範囲よりも少ない測定となり、Tuistは以前の実行からそれらのテストを引き継ぐことができません。そのコミットで他の実行がそれらを実行していない限り、コミットのカバレッジは**不完全**となります。コミットを完全な状態に保つには、コミットごとに少なくとも1回の実行ですべてのテストを実行してください。

隔離によってスキップされたテストはカバレッジに含まれないため、コミットが**不完全**になることはありません。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集にはオーバーヘッドが生じ、主にテスト終了後にXcodeがカバレッジレポートを書き込み、Tuistがカバレッジをエクスポートする間に発生します。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。

## カバレッジのクエリ {#querying}

`tuist coverage`コマンドは、ダッシュボードに表示されるデータを読み取ります。`--commit`を指定しない場合、`--branch`の最新の完了したコミット、またはデフォルトブランチの最新の完了したコミットを読み取ります：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

いずれのコマンドも、スクリプト用途のために`--json`を受け付けます。
