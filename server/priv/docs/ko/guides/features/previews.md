---
{
  "title": "Previews",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist Previews로 모바일 앱, 데스크톱 앱, 명령줄 도구를 공유하여 팀원이 로컬에서 다시 빌드하지 않고도 빌드를 시도할 수 있게 하세요."
}
---
# Previews {#previews}

Tuist Previews를 사용하면 팀원들이 모바일 앱, 데스크톱 앱, 명령줄 도구를 로컬에서 다시 빌드하지 않고도 사용해 볼 수 있습니다. 빌드를 Tuist 프로젝트에 게시한 후 미리보기 링크를 공유하세요.

## 미리보기 가능한 항목 {#what-you-can-preview}

- **모바일 앱:** Android APK 및 Apple 애플리케이션 번들 또는 IPA입니다. 지원되는 기기, 시뮬레이터 및 서명 요구 사항은 게시 워크플로에 따라 달라집니다.
- **데스크톱 앱:** macOS 애플리케이션 번들입니다.
- **명령줄 도구:** macOS 또는 Linux 실행 파일로, 단독으로 또는 종속성과 함께 번들링됩니다.

패키징 및 호환성 요구 사항은 <.localized_link href="/guides/features/previews/types">Supported types</.localized_link>을 참조하세요. 아티팩트 유형은 미리보기를 실행할 수 있는 위치를 결정하지만, 어떤 빌드 시스템이 이를 생성하는지는 지정하지 않습니다.

## 미리보기 게시 {#publish-a-preview}

설정 및 게시 명령에 사용할 빌드 시스템을 선택하세요:

<.home_cards>
  <.home_card
    title="Xcode"
    details="기존 Xcode 프로젝트 또는 Tuist가 생성한 프로젝트에서 애플리케이션을 공유합니다."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Gradle 프로젝트에서 Android 앱과 네이티브 명령줄 도구를 공유합니다."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="동반 Bazel 규칙을 사용하여 Android 앱, Apple 앱 및 명령줄 도구를 공유합니다."
    link="/guides/features/previews/bazel"
  />
</.home_cards>

이미 지원되는 빌드가 있는 경우, <.localized_link href="/cli/share">`tuist share`</.localized_link>을 사용하여 빌드 시스템 통합 없이 게시할 수 있습니다. 패키징 및 서명 요구 사항은 여전히 적용됩니다.

## 미리보기 실행 {#run-a-preview}

수신자는 미리보기를 생성한 빌드 시스템이 필요하지 않습니다. 호환되는 빌드에 액세스하는 방법을 선택하세요:

<.home_cards>
  <.home_card
    title="CLI"
    details="tuist run으로 모바일 앱, macOS 앱 및 명령줄 미리보기를 실행합니다."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS 앱"
    details="Tuist 메뉴 바 앱을 통해 호환되는 Apple 미리보기를 실행합니다."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone 앱"
    details="iPhone에서 Apple 미리보기를 찾아 액세스합니다."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## 공개 범위 {#visibility}

미리보기는 프로젝트의 기본 공개 범위를 사용합니다. 비공개 미리보기는 인증과 프로젝트 접근 권한이 필요합니다. 빌드를 누구나 공유할 수 있는 경우에만 프로젝트 설정에서 미리보기를 공개로 설정하세요. 공개 설정이라고 해서 플랫폼 서명이나 기기 설치 요구 사항이 우회되지는 않습니다.

## 트랙 {#tracks}

트랙은 미리보기를 이름이 지정된 그룹으로 정리하며, 예를 들어 내부 테스터용 `beta` 또는 자동화된 빌드용 `nightly`와 같이 사용됩니다. 워크플로에 맞게 게시 명령으로 트랙을 지정하세요. 트랙은 처음 사용될 때 지연 생성됩니다. 목적별로 미리보기를 그룹화하고 Tuist 대시보드에서 필터링하는 데 사용하세요.

## README 배지 {#readme-badge}

저장소의 `README`에 최신 미리보기로 연결되는 배지를 추가하세요:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

계정 및 프로젝트 핸들을 자신의 것으로 교체하세요:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

프로젝트에 서로 다른 번들 식별자를 가진 여러 앱이 포함된 경우, 앱을 선택하기 위해 `bundle-id` 쿼리 매개변수를 추가하세요:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
