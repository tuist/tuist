---
{
  "title": "デバッグ",
  "titleTemplate": ":title · コントリビューター · Tuist",
  "description": "コーディングエージェントとローカル実行を使用して、Tuist の問題をデバッグします。"
}
---
# デバッグ {#debugging}

オープンであることは実用的な利点です。コードが利用可能で、ローカルで実行でき、コーディングエージェントを使用して質問に迅速に答えたり、コードベースの潜在的なバグをデバッグしたりできます。

デバッグ中に不足している、または不完全なドキュメントを見つけた場合は、`server/priv/docs/en` の下の英語ドキュメントを更新し、PR を作成してください。

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

`TUIST_THREAD_DUMP_SAMPLE` が設定されていない場合、ハンドラは現在のスレッドスタックを表示します。出力は stderr に書き込まれるため、CI ログに表示されます。

## コーディングエージェントを使用する {#use-coding-agents}

コーディングエージェントは以下の用途に役立ちます。

- 特定の動作がどこで実装されているかをコードベースから探す。
- ローカルで問題を再現し、迅速に反復する。
- 入力が Tuist をどのように流れるかを追跡し、根本原因を見つける。

可能な限り最小限の再現手順を共有し、エージェントを特定のコンポーネント（CLI、サーバー、キャッシュ、ドキュメント、またはハンドブック）に向けてください。範囲が絞られているほど、デバッグプロセスはより迅速かつ正確になります。

### 頻繁に必要なプロンプト (FNP) {#frequently-needed-prompts}

#### 予期しないプロジェクト生成 {#unexpected-project-generation}

プロジェクト生成で予期しない結果が得られています。`/path/to/project` のプロジェクトに対して Tuist CLI を実行し、なぜこれが起こっているのかを理解してください。ジェネレーターパイプラインを追跡し、出力を担当するコードパスを特定してください。

#### 生成されたプロジェクトにおける再現可能なバグ {#reproducible-bug-in-generated-projects}

これは生成されたプロジェクトのバグのように見えます。`examples/` の下に、既存の例を参考にして再現可能なプロジェクトを作成してください。失敗する受け入れテストを追加し、そのテストのみを選択して `xcodebuild` で実行し、問題を修正して、テストが合格することを確認するために再実行し、PR を作成してください。
