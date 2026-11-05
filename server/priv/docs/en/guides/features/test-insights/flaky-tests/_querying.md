## Querying flaky and quarantined state {#querying}

### CLI {#querying-cli}

The `tuist test case` command tree exposes everything Tuist tracks about a test case:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

All of these accept `--json` for scripting.

### REST API {#querying-rest-api}

The same data is available over HTTP. See the [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) in the API reference for the full list of routes, filters, and response fields. To change a test case's state (mark or unmark flaky, mute, skip), send `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` with `is_flaky` or `state`. The same change is available as `tuist test case update` and as the `update_test_case` MCP tool.
