## 불안정하고 격리된 상태 쿼리하기 {#querying}

### CLI {#querying-cli}

`tuist test case` 명령어 트리는 Tuist가 테스트 케이스에 대해 추적하는 모든 정보를 제공합니다:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

이 모든 명령어는 스크립팅을 위해 `--json`를 지원합니다.

### REST API {#querying-rest-api}

동일한 데이터를 HTTP를 통해 사용할 수 있습니다. 전체 경로, 필터 및 응답 필드 목록은 API 참조의 [테스트 케이스 엔드포인트](https://tuist.dev/api/docs#tag/test-cases)를 참조하세요. 테스트 케이스의 상태(불안정 표시 또는 해제, 음소거, 건너뛰기)를 변경하려면 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`를 `is_flaky` 또는 `state`와 함께 전송하세요. 동일한 변경 사항은 `tuist test case update` 및 `update_test_case` MCP 도구를 통해서도 가능합니다.
