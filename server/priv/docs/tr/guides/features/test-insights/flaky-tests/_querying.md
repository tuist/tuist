## Kararsız ve karantinaya alınmış durum sorgulama {#querying}

### CLI {#querying-cli}

`tuist test case` komut ağacı, Tuist'in bir test senaryosu hakkında izlediği her şeyi sunar:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

Tüm bu komutlar betik yazımı için `--json` seçeneğini kabul eder.

### REST API {#querying-rest-api}

Aynı verilere HTTP üzerinden erişilebilir. Rotaların, filtrelerin ve yanıt alanlarının tam listesi için API referansındaki [Test Senaryoları uç noktaları](https://tuist.dev/api/docs#tag/test-cases) bölümüne bakın. Bir test senaryosunun durumunu değiştirmek (kararsız olarak işaretlemek veya işareti kaldırmak, sessize almak, atlamak) için `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` uç noktasına `is_flaky` veya `state` parametreleriyle istek gönderin. Aynı değişiklik `tuist test case update` komutu ve `update_test_case` MCP aracı aracılığıyla da yapılabilir.
