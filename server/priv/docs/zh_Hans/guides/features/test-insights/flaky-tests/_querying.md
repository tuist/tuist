## 查询不稳定和隔离状态 {#querying}

### CLI {#querying-cli}

`tuist test case` 命令树公开了 Tuist 跟踪的测试用例的所有信息：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有这些命令都接受 `--json` 以支持脚本化。

### REST API {#querying-rest-api}

相同的数据可通过 HTTP 获取。请参阅 API 参考中的 [测试用例端点](https://tuist.dev/api/docs#tag/test-cases)，了解完整的路由、过滤器和响应字段列表。要更改测试用例的状态（标记或取消标记为不稳定、静音、跳过），请发送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 并携带 `is_flaky` 或 `state`。同样的更改也可通过 `tuist test case update` 以及 `update_test_case` MCP 工具完成。
