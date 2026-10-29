---
{
  "title": "デバッグ",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "コーディングエージェントとローカル実行を使用して、Tuist の問題をデバッグします。"
}
---
# デバッグ {#debugging}

オープンであることは実用的な利点です。コードが利用可能で、ローカルで実行でき、コーディングエージェントを使って質問に迅速に答えたり、コードベースの潜在的なバグをデバッグしたりできます。

デバッグ中にドキュメントの欠落や不備を見つけた場合は、`docs/` 配下の英語ドキュメントを更新して PR を作成してください。

## CI でスレッドダンプを取得する {#thread-dump-ci}

CLI が断続的にハングする場合、プロセスを停止せずにスレッドダンプを取得できます。シグナルハンドラを有効にし、実行中の `tuist` プロセスに `SIGUSR1` を送信してください。

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

- 特定の動作がコードベースのどこで実装されているかをスキャンする
- 問題をローカルで再現し、迅速に試行錯誤する
- Tuist 内での入力の流れを追跡し、根本原因を特定する

可能な限り最小限の再現手順を共有し、エージェントを対象のコンポーネント（CLI、サーバー、キャッシュ、ドキュメント、またはハンドブック）に向けてください。範囲を絞るほど、デバッグプロセスは迅速かつ正確になります。

### 頻繁に必要なプロンプト（FNP） {#frequently-needed-prompts}

#### 予期しないプロジェクト生成 {#unexpected-project-generation}

プロジェクト生成が期待と異なる結果を返しています。`/path/to/project` のプロジェクトに対して Tuist CLI を実行し、なぜこうなるのかを理解してください。ジェネレーターのパイプラインを追跡し、出力に関与するコードパスを特定してください。

#### 生成されたプロジェクトにおける再現可能なバグ {#reproducible-bug-in-generated-projects}

生成されたプロジェクトのバグのようです。`examples/` 配下に再現可能なプロジェクトを作成し、既存の例を参考にしてください。失敗する受け入れテストを追加し、そのテストのみを選択して `xcodebuild` で実行し、問題を修正して、テストがパスすることを確認するために再実行し、PR を作成してください。
