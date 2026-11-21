---
{
  "title": "Xcodeコードカバレッジ",
  "titleTemplate": ":title · コードカバレッジ · 機能 · ガイド · Tuist",
  "description": "XcodeプロジェクトのコードカバレッジをTuistにアップロードし、ファイルごとおよびコミットごとに追跡します。"
}
---
# Xcode のコードカバレッジ {#xcode-code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuist は各テスト実行の行カバレッジをアップロードし、コミット内の実行をプロジェクト、各ターゲット、各ファイルごとに1つの数値に集約します。ダッシュボードの **コードカバレッジ** ページでは、コミットごとの値とブランチごとのトレンドを表示します。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Tuist でプロジェクトを生成している場合は、代わりに <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成されたプロジェクトのガイド</.localized_link> に従ってください。このガイドでは、バイナリキャッシュから提供されるコードを測定し、選択的テストでスキップされたテストターゲットのカバレッジを引き継ぐ方法について説明しています。

## セットアップ {#setup}

### カバレッジの収集 {#collect-coverage}

`Tuist.swift` でカバレッジのアップロードを有効にしてください。デフォルトでは無効になっています。

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 環境変数（`1` または `0`）はオプションよりも優先され、例えばフォークからのプルリクエストを実行するジョブでアップロードを無効にする場合に使用できます。

次に、スキームのテストアクション（**Edit Scheme › Test › Options**）で **コードカバレッジ** を有効にするか、実行時に `-enableCodeCoverage YES` を渡して、`tuist xcodebuild test` を介してテストを実行します。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist は、実行中に収集されたカバレッジをテスト結果とともにアップロードします。

### CI で各コミットを完了させる {#complete-each-commit}

コミットのカバレッジは、複数のジョブ（スキームごと、シャードごと、またはプラットフォームごと）から得られることがよくあります。Tuist は最後に報告されたジョブを自動で検出できないため、明示的に通知する必要があります。コミットに関連するすべてのテストジョブが終了したら、それらすべてに依存するジョブで次のコマンドを実行します。

```sh
tuist coverage complete
```

このコマンドは、チェックアウトの `HEAD`（テストが実行されたコミット）からコミットを読み取ります。別のコミットを指定するには `--commit <sha>` を渡してください。コミットが完了するまで、そのカバレッジは **進行中** と表示され、ブランチのトレンドには含まれません。各ステータスの詳細は <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成されたプロジェクトのガイド</.localized_link> で説明されています。

## スキップされたテスト {#skipped-tests}

実行が `-skip-testing` でテストをスキップする場合、そのコミットのテストがカバーする範囲よりも少ない測定となり、Tuist は以前の執行からそれらのテストを引き継ぐことができません。そのコミットでの別の実行がそれらを実行しない限り、コミットのカバレッジは **不完全** となります。コミットを完全な状態に保つには、コミットごとに少なくとも1回の実行ですべてのテストを実行してください。

隔離によってスキップされたテストはカバレッジに含まれないため、コミットが **不完全** になることはありません。

## パフォーマンスへの影響 {#performance-impact}

カバレッジの収集にはオーバーヘッドが生じ、主にテスト終了後に Xcode がカバレッジレポートを書き込み、Tuist がカバレッジをエクスポートする間に発生します。テストのビルドと実行にかかる時間は、カバレッジなしの場合とほぼ同じです。

## カバレッジの問い合わせ {#querying}

`tuist coverage` コマンドは、ダッシュボードに表示される情報を読み取ります。`--commit` を指定しない場合、`--branch` またはデフォルトブランチの最新の完了したコミットの情報を読み取ります。

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

テスト実行自体のカバレッジは `tuist test show <test-run-id>` で確認できます。

すべて `--json` を受け付け、スクリプトでの利用が可能です。
