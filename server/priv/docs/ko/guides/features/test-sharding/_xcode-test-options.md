### 테스트 옵션 {#test-options}

| 플래그 | 환경 변수 | 설명 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 실행할 샤드의 0부터 시작하는 인덱스 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 빌드 단계에서 생성된 정확한 샤드 플랜 식별자. 생성된 프로바이더 출력에는 이 값이 자동으로 포함됩니다 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 샤드 플랜의 고유 식별자(지원되는 CI 프로바이더에서 자동 파생) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 로컬로 관리되는 샤드 아카이브 경로; Tuist는 원격 스토리지에서 테스트 제품을 다운로드하는 대신 이를 추출합니다 |

Tuist는 `.xctestproducts` 번들을 다운로드하고 해당 샤드에 할당된 테스트만 포함하도록 필터링합니다.
