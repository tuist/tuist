---
{
  "title": "Gradle",
  "titleTemplate": ":title · 스냅샷 · 기능 · 가이드 · Tuist",
  "description": "Tuist Gradle 플러그인으로 모든 Compose 미리보기를 스냅샷하거나, Paparazzi와 Roborazzi가 기록한 내용을 업로드하세요."
}
---
# Gradle 스냅샷 {#gradle-snapshots}

> [!IMPORTANT]
> **요구 사항**
>
> - 계정에 스냅샷이 활성화되어 있어야 합니다. 현재는 초대 전용입니다: [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 접근 권한을 요청하세요.
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 플러그인</.localized_link>.
> - 스냅샷을 찍는 모듈에 [Paparazzi](https://github.com/cashapp/paparazzi) 또는 [Roborazzi](https://github.com/takahirom/roborazzi)가 포함되어 있어야 합니다.

Tuist Gradle 플러그인은 Paparazzi와 Roborazzi가 기록한 이미지를 업로드하고, Tuist는 이를 <.localized_link href="/guides/features/snapshots#how-it-works">베이스라인</.localized_link>과 비교합니다. Paparazzi를 적용한 모듈에서는 플러그인이 모든 Compose `@Preview`를 렌더링하는 테스트도 생성하므로, 스냅샷 테스트를 직접 작성할 필요가 없습니다.

## 설정하기 {#set-up}

`settings.gradle.kts`에서 스냅샷을 활성화하세요:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## 실행하기 {#run}

CI 환경에서 `./gradlew test`는 프리뷰를 렌더링하고 업로드하며, 변경되었는데 아무도 승인하지 않으면 빌드가 실패합니다. 로컬 실행은 커밋되지 않은 변경 사항을 업로드하지 않도록 아무것도 업로드하지 않습니다. CI에서 업로드를 비활성화하려면 `-Ptuist.snapshots=false` 옵션을 전달하세요.

Paparazzi와 Roborazzi의 기록 태스크(예: `recordPaparazziDebug`)는 스냅샷이 활성화되면 항상 업로드합니다.

## 옵션 {#options}

`snapshots` 블록은 다음 옵션을 받습니다:

- `enabled`: 스냅샷 업로드 여부. 기본값은 `false`입니다.
- `set`: 빌드를 비교할 집합. 기본값은 Gradle 프로젝트의 경로입니다.
- `directory`: Gradle 프로젝트 기준 업로드할 이미지가 있는 디렉터리. 기본값은 생성된 프리뷰 테스트나 스냅샷 라이브러리가 기록하는 위치입니다.
- `failOnChanges`: 아무도 승인하지 않은 변경 사항이 있을 때 빌드 실패 여부. 기본값은 `true`입니다.
- `diffThreshold`: 이미지가 변경된 것으로 간주되기 전에 다를 수 있는 픽셀 비율(0~1). 기본값은 `0`입니다.
- `previews { generateTests }`: Compose 프리뷰 테스트 생성 여부. 기본값은 `true`입니다.
- `previews { packageTrees }`: 프리뷰를 검색할 패키지. 기본값은 Android 네임스페이스입니다.
- `previews { includePrivatePreviews }`: 비공개 `@Preview` 함수도 렌더링 여부. 기본값은 `false`입니다.
- `previews { theme }`: 프리뷰를 렌더링할 Android 테마. 기본값은 Paparazzi의 테마입니다.
