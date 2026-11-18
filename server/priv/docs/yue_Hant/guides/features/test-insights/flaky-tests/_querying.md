## 查詢不穩定及隔離狀態 {#querying}

### CLI {#querying-cli}

`tuist test case` 命令樹公開 Tuist 追蹤測試案例的所有資料：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

以上所有命令均支援 `--json`，方便編寫腳本。

### REST API {#querying-rest-api}

同樣的資料可透過 HTTP 取得。請參閱 API 參考文件中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以查看完整的路由、篩選條件及回應欄位清單。如要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請傳送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky` 或 `state`。相同的變更亦可透過 `tuist test case update` 及 `update_test_case` MCP 工具進行。
