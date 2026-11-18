## არასტაბილური და კარანტინში მყოფი მდგომარეობის მოთხოვნა {#querying}

### CLI {#querying-cli}

`tuist test case` ბრძანებების ხე საშუალებას გაძლევთ ნახოთ ყველა ინფორმაცია, რასაც Tuist აკვირდება სატესტო შემთხვევის შესახებ:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

ყველა ეს ბრძანება იღებს `--json` პარამეტრს სკრიპტებისთვის.

### REST API {#querying-rest-api}

იგივე მონაცემები ხელმისაწვდომია HTTP-ით. სრული სიისთვის (მარშრუტები, ფილტრები და პასუხის ველები) იხილეთ [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) API-ის ცნობარში. სატესტო შემთხვევის მდგომარეობის შესაცვლელად (არასტაბილურად მონიშვნა/მოხსნა, ჩუმად დატოვება, გამოტოვება), გააგზავნეთ `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` პარამეტრებით `is_flaky` ან `state`. იგივე ცვლილების განხორციელება შესაძლებელია ასევე `tuist test case update` ბრძანებით და `update_test_case` MCP ინსტრუმენტით.
