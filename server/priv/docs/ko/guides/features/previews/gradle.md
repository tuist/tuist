---
{
  "title": "Gradle 미리보기",
  "titleTemplate": ":title · 미리보기 · Tuist",
  "description": "Tuist Previews로 Gradle 프로젝트에서 Android 앱과 네이티브 명령줄 도구를 빌드하고 공유하세요."
}
---
# Gradle 프리뷰

Android 앱과 네이티브 명령줄 도구를 Gradle에서 직접 빌드하고 공유하세요. 프로젝트를 연결하고 인증하려면 <.localized_link href="/guides/get-started/gradle-project">Gradle 프로젝트 가이드</.localized_link>부터 시작하세요.

## Android 앱

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 설정 플러그인은 Android Gradle Plugin(8.8.2 이상)의 각 애플리케이션 변형(variant)에 대해 `tuistShare<Variant>` 태스크를 등록합니다. `app`와 `Debug`를 애플리케이션 모듈과 변형으로 바꾸세요. 예를 들어 제품 flavor에는 `:app:tuistShareDemoDebug`를 사용합니다. 이 태스크는 APK를 게시하기 전에 Gradle이 선언한 아티팩트 의존성을 통해 빌드합니다. 빌드 결과물이 최신 상태이거나 빌드 캐시에서 복원된 경우에도 작동합니다.

서명된 단일 범용 애플리케이션 APK만 지원됩니다. Android의 디버그 변형은 일반적으로 디버그 서명 키를 사용하며, 릴리스 변형에는 자체 서명 구성이 필요합니다. 이 태스크는 인증 또는 업로드 전에 APK 서명을 검증합니다. 서명되지 않거나 유효하지 않은 APK, 인스트루먼테이션 APK, 분할 APK는 거부됩니다. 라이브러리 모듈, 테스트 APK, Android App Bundle(`.aab`)은 게시 대상이 아닙니다.

## 네이티브 명령줄 도구

Gradle의 `cpp-application` 또는 `swift-application` 플러그인을 사용하는 프로젝트는 각 네이티브 바이너리에 대해 공유 태스크를 제공합니다.

```bash
./gradlew :app:tuistShareMainDebug
```

이 태스크는 런처와 런타임 라이브러리를 포함하여 설치된 배포판을 빌드하고 패키징합니다. 릴리스 바이너리에는 `tuistShareMainRelease`를 사용하세요. 여러 머신을 대상으로 하는 프로젝트는 각 바이너리마다 태스크가 있으며, `./gradlew :app:tasks --all`를 실행하여 이름을 확인할 수 있습니다.

arm64 또는 x86_64용 네이티브 macOS 및 Linux 실행 파일이 지원됩니다. Gradle 플러그인이 요구하는 툴체인을 사용하여 대상 플랫폼에서 빌드하세요. JVM 애플리케이션과 생성된 런처 스크립트는 이 통합에서 지원되지 않습니다.

## 게시 동작

공유 태스크는 Tuist CLI를 호출하지 않고 플러그인의 기존 Tuist 자격 증명을 사용하여 게시합니다. 일반적인 `assemble`, `build` 및 테스트 태스크는 프리뷰를 게시하지 않습니다.

공유 후 프로젝트에서 **프리뷰**를 열어 링크를 복사하세요. 동일한 빌드와 트랙을 다시 공유하면 빌드 캐시 히트 이후에도 해당 게시물을 재사용합니다. 업로드가 실패하거나 확인되지 않으면 공유 태스크가 실패하며, 성공적인 프리뷰로 보고되지 않습니다.

## CI 및 트랙

플러그인의 다른 인증된 기능에 사용하는 것과 동일한 자격 증명으로 <.localized_link href="/guides/integrations/continuous-integration">CI 인증</.localized_link>을 구성한 다음 명시적으로 게시를 요청하세요.

```bash
./gradlew :app:tuistShareDebug --track nightly
```

네이티브 공유 태스크에도 같은 방식으로 `--track nightly`를 추가하세요. 태스크는 구성된 Tuist 프로젝트, 서버 URL 및 프록시 설정을 사용합니다. 프리뷰 게시에는 항상 인증이 필요합니다. Git 리비전 메타데이터, 릴리스 노트, 자동 풀 리퀘스트 댓글은 이러한 태스크에 첨부되지 않습니다.

호스팅된 Tuist에서는 아티팩트 게시물이 30일 후에 만료됩니다. 자체 호스팅 인스턴스는 `TUIST_APP_PREVIEW_RETENTION_DAYS`를 사용하며, 이를 설정하지 않으면 이 계열의 만료가 비활성화됩니다. 만료된 게시물은 동일한 의도를 반복해서 부활시킬 수 없습니다.

## 기존 APK 공유

이 워크플로우 외부에서 빌드된 APK의 경우 또는 레거시 업로드 흐름으로 릴리스 노트를 포함하려면 CLI를 계속 사용할 수 있습니다.

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

게시된 빌드 실행, 접근 권한, 트랙 및 README 배지에 대해서는 <.localized_link href="/guides/features/previews#run-a-preview">프리뷰 실행</.localized_link>을 참조하세요.

<!-- @snippet: ./_tuist-share -->
