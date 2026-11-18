## 查詢不穩定與隔離狀態 {#querying}

### CLI {#querying-cli}

`tuist test case` 命令樹公開 Tuist 針對測試案例追蹤的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

這些指令皆支援 `--json`，方便撰寫腳本。

### REST API {#querying-rest-api}

相同資料可透過 HTTP 取得。請參閱 API 參考文件中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以取得完整的路由、篩選器與回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、略過），請傳送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky` 或 `state`。相同的變更也可透過 `tuist test case update` 以及 `update_test_case` MCP 工具完成。
