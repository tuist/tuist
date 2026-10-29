---
{
  "title": "Gradle Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Gradle test analytics in the Tuist dashboard to monitor test performance."
}
---
# Gradle 테스트 인사이트 {#gradle-test-insights}

Tuist의 Gradle 플러그인은 각 테스트 작업 실행 후 테스트 결과를 자동으로 업로드하여, Tuist 대시보드에서 직접 테스트 성능과 불안정한 테스트(flaky tests)에 대한 가시성을 제공합니다.

Tuist Gradle 플러그인이 적용되면 테스트 인사이트가 자동으로 수집됩니다. 초기 플러그인 설정 외에 추가 구성이 필요하지 않습니다.

Tuist 대시보드에서 테스트 인사이트에 접근하고 시간이 지남에 따라 어떻게 변화하는지 확인할 수 있습니다:

![테스트 인사이트가 포함된 대시보드](/images/guides/features/build-insights/tests-dashboard.png)

## 추적 대상 {#what-is-tracked}

플러그인은 모든 Gradle `Test` 작업의 결과를 수집하며, 다음을 포함합니다:
- 개별 테스트 케이스의 통과/실패 상태 및 소요 시간
- 테스트 스위트 및 클래스 구조
- 실행 간 불안정한 테스트(flaky test) 감지

## 업로드 동작 구성 {#configure-upload-behavior}

기본값:
- 로컬 빌드의 경우 테스트 결과가 백그라운드에서 업로드됩니다.
- CI 실행의 경우 짧은 수명의 에이전트에서 텔레메트리 데이터가 손실되는 것을 방지하기 위해 테스트 결과가 포그라운드에서 업로드됩니다.

`settings.gradle.kts`의 `tuist` 블록에서 `uploadInBackground`를 사용하여 이 동작을 재정의할 수 있습니다:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git 히스토리 {#git-history}

CI 환경에서는 플러그인이 테스트 실행을 보고할 때 체크아웃의 커밋 히스토리도 함께 업로드합니다: 커밋 SHA, 부모 커밋, 커밋 날짜, 그리고 해당 실행과 풀 리퀘스트의 기본 브랜치가 속한 브랜치 정보입니다. 파일 내용, 커밋 메시지 또는 작성자는 업로드되지 않습니다. 이를 통해 Tuist는 예를 들어 병합 큐(merge queue)에서 테스트된 커밋 중 어떤 커밋이 기본 브랜치에 반영되었는지 파악할 수 있습니다. 플러그인은 체크아웃에 이미 있는 히스토리를 읽으며, 체크아웃에 기본 브랜치가 없는 경우 원격 저장소에 최신 커밋을 요청합니다(`git ls-remote`). 히스토리를 가져오지는 않습니다.

| 변수 | 효과 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 히스토리를 읽거나 업로드하지 않습니다. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 원격 저장소에 연결하지 않고 체크아웃만 읽습니다. |
