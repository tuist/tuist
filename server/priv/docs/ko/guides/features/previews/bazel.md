---
{
  "title": "Bazel 프리뷰",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Bazel에서 Android 앱, Apple 앱 및 명령줄 도구를 프리뷰로 게시합니다."
}
---
# Bazel 미리보기

기존 Bazel 대상에서 Android APK, Apple 시뮬레이터 및 macOS 앱, 명령줄 도구를 게시하세요. 공유하려는 각 출력물에 대해 미리보기 대상을 추가하면 일반 빌드는 변경되지 않습니다.

## 설정

사용할 커밋을 고정하여 Tuist 리포지토리의 [`rules_tuist` ](https://github.com/tuist/tuist/tree/main/bazel)를 `MODULE.bazel` 에 추가하세요:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

기존 애플리케이션 대상, 네이티브 SDK 및 서명 설정은 그대로 유지하세요. 게시 도구는 Bazel이 제공합니다.

Bazel에서 직접 로그인하세요:

```bash
bazel run @rules_tuist//:login
```

이는 Tuist CLI 및 Gradle 플러그인과 자격 증명을 공유하며, 기존 로그인도 작동합니다. CI에서는 `TUIST_TOKEN` 을 사용하거나 Tuist의 <.localized_link href="/guides/integrations/continuous-integration">OIDC 인증</.localized_link> 으로 로그인 대상을 실행하세요. BUILD 파일이나 규칙 속성에 자격 증명을 넣지 마세요. 자체 호스팅 인스턴스에 로그인하려면 `-- --url https://tuist.example.com` 을 전달하세요.

`BUILD.bazel` 에서 필요한 어댑터만 로드하세요:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Apple 애플리케이션용:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

`cc_binary` 와 같은 실행 가능 대상용:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

실행 가능 미리보기에는 대상에 선언된 런타임 파일이 포함됩니다. 도구에 필요한 라이브러리와 리소스를 Bazel 대상에 선언하고, 빌드 디렉터리 외부에서도 작동하는 경로를 사용하세요.

## 빌드 및 게시

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

애플리케이션 및 시뮬레이터 플랫폼 라벨을 자신의 것으로 교체하세요. 자체 호스팅 Tuist 출처에는 `--url` 을, Git 커밋을 연결하려면 `--revision` 를 전달하세요.

성공한 빌드를 공유하려면 `--publish --project account/project` 을 전달하세요. `--publish` 가 없거나 `--no-publish` 이면 아무 것도 업로드되지 않으며 로그인이 필요하지 않습니다. 일반 `bazel build` 은 캐시 히트 시에도 게시하지 않습니다. `tuist bazel setup` 는 게시가 아닌 캐싱과 인사이트를 활성화합니다.

## 지원되는 출력물

- **Android:** 디버그 빌드를 포함한 서명된 애플리케이션 APK. Android SDK 빌드 도구 및 명령줄 도구를 설치하고 `ANDROID_HOME` 또는 `ANDROID_SDK_ROOT` 을 설정하세요. 테스트 APK와 Android App Bundles는 지원되지 않습니다.
- **Apple:** macOS에서 빌드되고 검증된 ad-hoc 서명된 시뮬레이터 및 macOS 애플리케이션. 물리적 기기 빌드, 프레임워크, 확장 프로그램 및 테스트는 지원되지 않습니다. 실험적 트리 아카이브 대신 아카이브 출력을 사용하세요.
- **명령줄 도구:** arm64 또는 x86_64용 macOS 또는 Linux 실행 파일(범용 macOS 바이너리 포함). 스크립트는 수신자 시스템에 shebang과 인터프리터가 필요합니다. 대상에 런타임 종속성을 선언하세요. Tuist는 누락된 라이브러리나 언어 런타임을 설치하지 않습니다.

## 캐시 재사용, 실패 및 보존

동일한 게시를 반복하면 Bazel이 캐시에서 빌드를 복원하더라도 기존 미리보기를 다시 업로드하지 않고 재사용합니다. 출력물, 트랙 또는 리비전을 변경하면 새 게시물이 생성됩니다. 업로드 실패 시 명령이 실패하며, 다시 시도하기 전에 게시가 완료되었는지 확인하기 위해 다시 실행할 수 있습니다.

명령은 프로젝트의 미리보기로 링크되며, 처리에 잠시 시간이 걸릴 수 있습니다. 미리보기는 프로젝트의 기본 가시성을 사용합니다.

호스팅된 Tuist에서는 아티팩트 게시가 30일 후에 만료됩니다. 자체 호스팅 인스턴스는 `TUIST_APP_PREVIEW_RETENTION_DAYS` 을 사용하며, 이를 설정하지 않으면 이 계열의 만료가 비활성화됩니다. 만료된 게시 기록은 동일한 의도를 재실행하여 복구할 수 없습니다.

게시된 빌드 실행, 액세스, 트랙 및 README 배지에 대해서는 <.localized_link href="/guides/features/previews#run-a-preview">미리보기 실행</.localized_link> 을 참조하세요.

## Apple 미리보기

Apple 시뮬레이터 및 macOS 미리보기에 대해서는 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 동반 앱 지침</.localized_link> 을 참조하세요. 이는 Bazel의 애플리케이션 자격 조건이나 서명 요구 사항을 변경하지 않습니다.

## 관련 워크플로 {#publish-from-once}

기존 Struo 통합에는 별도의 <.localized_link href="/guides/features/previews/struo">아티팩트 게시 가이드</.localized_link> 가 있습니다. 두 워크플로 모두 게시를 캐시된 그래프 실행과 분리하여 유지합니다.
