### 빌드 옵션 {#build-options}

| 플래그 | 환경 변수 | 설명 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 최대 샤드 수. `--shard-max-duration`와 함께 사용하여 샤드 수를 제한합니다. |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 최소 샤드 수 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 정확한 샤드 수(`--shard-min`/`--shard-max`와 상호 배타적). 스위트 단위의 경우 마지막 샤드가 나머지 모든 항목을 포함합니다. |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 샤드당 목표 최대 지속 시간(밀리초) |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`(기본값)은 전체 테스트 모듈을 샤드에 분배하고, `suite`는 더 세밀한 균형을 위해 개별 테스트 클래스를 분배합니다. |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 샤드 계획의 고유 식별자(지원되는 CI 제공업체에서 자동으로 파생됨) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist가 테스트 제품을 원격 스토리지에 업로드하는 대신 최적화된 샤드 아카이브를 기록하는 경로 |
