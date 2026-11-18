---
{
  "title": "デバッグ",
  "titleTemplate": ":title · コントリビューター · Tuist",
  "description": "コーディングエージェントとローカル実行を使用して、Tuist の問題をデバッグします。"
}
---
# デバッグ {#debugging}

オープンであることは実用的な利点です。コードが公開されており、ローカルで実行でき、コーディングエージェントを使って質問にすばやく答えたり、コードベースの潜在的なバグをデバッグしたりできます。

デバッグ中にドキュメントの欠落や不備を見つけた場合は、`server/priv/docs/en` 以下の英語ドキュメントを更新して PR を作成してください。

## CI でスレッドダンプを取得する {#thread-dump-ci}

CLI が断続的にハングする場合、プロセスを停止せずにスレッドダンプを取得できます。シグナルハンドラを有効にし、実行中の `tuist` プロセスに `SIGUSR1` を送信します。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

`TUIST_THREAD_DUMP_SAMPLE` が設定されていない場合、ハンドラは現在のスレッドスタックを出力します。出力は stderr に書き込まれるため、CI ログに表示されます。

## コーディングエージェントを活用する {#use-coding-agents}

コーディングエージェントは次のような場面で役立ちます。

- 特定の動作がどこで実装されているかをコードベースから探す。
- 問題をローカルで再現し、すばやく試行錯誤する。
- 入力が Tuist をどのように流れるかを追跡し、根本原因を特定する。

可能な限り最小の再現手順を共有し、対象となるコンポーネント（CLI、サーバー、キャッシュ、ドキュメント、またはハンドブック）をエージェントに指定してください。範囲を絞るほど、デバッグプロセスは迅速かつ正確になります。

### 頻繁に必要になるプロンプト（FNP） {#frequently-needed-prompts}

#### 予期しないプロジェクト生成 {#unexpected-project-generation}

プロジェクト生成の結果が期待と異なります。`/path/to/project` のプロジェクトに対して Tuist CLI を実行し、なぜこうなるのかを調べます。ジェネレーターのパイプラインを追跡し、出力を生み出しているコードパスを特定してください。

#### 生成されたプロジェクトにおける再現可能なバグ {#reproducible-bug-in-generated-projects}

生成されたプロジェクトのバグのようです。`examples/` 以下に再現可能なプロジェクトを作成し、既存の例を参考にしてください。失敗する受け入れテストを追加し、そのテストのみを選択して `xcodebuild` で実行します。問題を修正し、テストを再実行して合格することを確認してから、PR を作成してください。
