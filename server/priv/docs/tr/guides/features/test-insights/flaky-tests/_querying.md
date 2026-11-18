## Kararsız ve karantinaya alınmış durumu sorgulama {#querying}

### CLI {#querying-cli}

`tuist test case` komut ağacı, Tuist'in bir test senaryosu hakkında izlediği her şeyi ortaya çıkarır:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

Bunların tümü betik yazımı için `--json` kabul eder.

### REST API {#querying-rest-api}

Aynı verilere HTTP üzerinden erişilebilir. Rotaların, filtrelerin ve yanıt alanlarının tam listesi için API referansındaki [Test Senaryoları uç noktalarını](https://tuist.dev/api/docs#tag/test-cases) inceleyin. Bir test senaryosunun durumunu değiştirmek için (kararsız olarak işaretleme veya işaretini kaldırma, sessize alma, atlama), `is_flaky` veya `state` ile birlikte `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` gönderin. Aynı değişiklik `tuist test case update` olarak ve `update_test_case` MCP aracı olarak da kullanılabilir.
