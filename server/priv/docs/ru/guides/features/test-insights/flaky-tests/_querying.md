## Запрос состояния нестабильных и изолированных тестов {#querying}

### CLI {#querying-cli}

Дерево команд `tuist test case` предоставляет всю информацию, которую Tuist отслеживает о тест-кейсе:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

Все эти команды поддерживают `--json` для использования в скриптах.

### REST API {#querying-rest-api}

Те же данные доступны по HTTP. См. [эндпоинты тест-кейсов](https://tuist.dev/api/docs#tag/test-cases) в справочнике API для получения полного списка маршрутов, фильтров и полей ответа. Чтобы изменить состояние тест-кейса (отметить или снять отметку о нестабильности, игнорировать, пропустить), отправьте `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` с параметром `is_flaky` или `state`. То же изменение доступно через команду `tuist test case update` и инструмент MCP `update_test_case`.
