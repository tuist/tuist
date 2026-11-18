## 사용자 정의 메타데이터 {#custom-metadata}

환경 변수를 사용하여 빌드에 메타데이터를 첨부하면 필터링을 개선할 수 있습니다.

### 환경 변수

| 변수 | 형식 | 설명 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 쉼표로 구분 | 하나의 변수에 여러 태그를 포함합니다. |
| `TUIST_BUILD_VALUE_*` | 단일 값 | 접미사가 키인 키-값 쌍입니다. |

### 예시

빌드를 실행하기 전에 CI 또는 셸에서 이러한 값을 설정하세요:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
