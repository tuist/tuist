---
{
  "title": "Bazel Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Bazel command duration, cache totals, and critical-path diagnostics in the Tuist dashboard."
}
---
# Bazel ビルドインサイト {#bazel-build-insights}

完了したすべての `build`、`test`、およびその他の Bazel コマンドは、プロジェクトの **Invocations** ダッシュボードに表示されます。コマンドの種類、終了ステータス、開始時刻と終了時刻、所要時間、そしてその呼び出しに Bazel が帰属させたキャッシュヒット、ミス、ダウンロード、アップロードが含まれます。

呼び出しデータは Bazel の [Build Event Protocol](https://bazel.build/remote/bep) を介して配信されます。`tuist bazel setup` を実行するとセットアップにより自動的に組み込まれるため、呼び出しを表示し始めるために追加のフラグは必要ありません。

## ダッシュボードに表示される内容 {#what-the-dashboard-shows}

各呼び出しでは以下の情報を記録します：

- Bazel が実行したコマンド、その終了コード、開始時刻と終了時刻、および合計所要時間。
- アクション、ターゲット、およびパッケージの数。
- 制限付きビルドタイムラインとクリティカルパスの概要。
- 呼び出しに帰属するキャッシュヒット、ミス、ダウンロード、およびアップロード。
- 実行中にキャプチャされた進捗ログの行（実行順序）。
- Bazel バージョン、Bazel が報告する場合の git ブランチとコミット、および CI で実行されたかどうか。

Bazel が完了した呼び出しに帰属できないキャッシュアクティビティ（例えば、コマンドの実行中に中断された場合）は、生のリモートキャッシュ観測値としてプロジェクトの **Overview** に表示されます。これはコマンドの成功、所要時間、またはテスト結果の証拠としては扱われません。

## カスタムメタデータ {#custom-metadata}

異なるチーム、ハードウェア、またはワークフローからの実行を比較するために、キーと値のデータを呼び出しに添付できます。値は各呼び出しの詳細ページ、アプリケーションプログラミングインターフェース、および Model Context Protocol ツールを通じて表示されます。

Bazel の組み込み `--build_metadata` フラグを使用してメタデータを設定します：

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

または、`.bazelrc` でレーンごとに一度設定します：

```text
build:ci --build_metadata=RUNNER=macos-14
```

各呼び出しには最大 20 個のカスタムエントリを含めることができます。キーは最大 50 文字、値は最大 500 文字まで含めることができます。これらの制限を超えるエントリは呼び出しが保存される前に削除されるため、無効なエントリがあってもレポートの残りの部分が記録されるのを妨げることはありません。

Tuist がビルド環境から導出するコンテキストキー（`CI`、`GIT_BRANCH`、`GIT_COMMIT` など）は、呼び出しの主要フィールドにすでに設定されているため、カスタム値として保存されません。

カスタムメタデータは、ダッシュボード、アプリケーションプログラミングインターフェース、および Model Context Protocol ツールを通じてプロジェクトメンバーに表示されます。認証情報、アクセストークン、またはその他の機密データには使用しないでください。

## オプトアウト {#opting-out}

Build Event Protocol ストリームには、コマンドライン引数、環境変数、およびコマンド出力が含まれます。Tuist は上記の完了したコマンドのフィールドのみを保持し、残りを破棄しますが、イベントストリームをまったく送信したくない場合は、次のコマンドでセットアップを再実行してください：

```bash
tuist bazel setup --no-build-insights
```

生成された `.bazelrc.tuist` はリモートキャッシュのみを設定します。呼び出しはダッシュボードに表示されなくなり、キャッシュ観測値は **Overview** ページに残ります。

## データ保持 {#data-retention}

Tuist は Bazel の呼び出しとそのログを 90 日間保持します。完全なポリシーについては <.localized_link href="/guides/server/data-retention">データ保持</.localized_link> を参照してください。
