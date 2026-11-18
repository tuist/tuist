## 不安定および隔離状態のクエリ {#querying}

### CLI {#querying-cli}

`tuist test case` コマンドツリーは、Tuist がテストケースについて追跡するすべての情報を公開します。

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

これらはすべて、スクリプト用に `--json` を受け入れます。

### REST API {#querying-rest-api}

同じデータは HTTP 経由で利用できます。ルート、フィルター、レスポンスフィールドの完全なリストについては、API リファレンスの [テストケースエンドポイント](https://tuist.dev/api/docs#tag/test-cases) を参照してください。テストケースの状態（不安定のマークまたは解除、ミュート、スキップ）を変更するには、`is_flaky` または `state` を指定して `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` を送信してください。同じ変更は `tuist test case update` および `update_test_case` MCP ツールとしても利用できます。
