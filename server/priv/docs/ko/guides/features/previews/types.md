---
{
  "title": "지원되는 미리보기 유형",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "모바일 앱, macOS 앱 및 명령줄 미리보기를 위한 패키징 및 호환성 요구 사항."
}
---
# 지원되는 프리뷰 유형

프리뷰 유형은 이를 생성하는 빌드 시스템과 무관하게 패키징 대상과 실행 환경을 결정합니다. 각 배포 워크플로에는 고유한 서명 및 자격 요건이 있습니다.

## 모바일 앱 {#mobile-apps}

- **Android:** 서명된 애플리케이션 APK입니다. 수신자는 호환되는 Android 기기 또는 에뮬레이터가 필요합니다. Android App Bundle(`.aab`)은 프리뷰 설치 패키지가 아닙니다.
- **Apple:** 시뮬레이터용 애플리케이션 번들이거나 물리적 기기용 내보낸 IPA입니다. 기기 빌드는 수신자의 기기에 설치를 허용하는 프로비저닝 프로파일이 필요합니다.

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>, <.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> 및 <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> 가이드는 각 워크플로가 게시할 수 있는 출력을 설명합니다. 예를 들어, Bazel과 Once 배포는 적절한 Apple 시뮬레이터 및 macOS 애플리케이션을 지원하지만, 물리적 기기 빌드는 지원하지 않습니다.

## 데스크톱 앱 {#desktop-apps}

빌드된 macOS 애플리케이션 번들을 공유하세요:

```bash
tuist share path/to/MyApp.app
```

서명 및 공증 요구 사항은 여전히 적용됩니다. 데스크톱 애플리케이션 번들은 수신자가 프리뷰를 실행하는 데 사용할 수 있는 Tuist macOS 앱과 다릅니다.

## 명령줄 도구 {#command-line-tools}

macOS 또는 Linux에서 독립형 실행 파일을 공유하세요:

```bash
tuist share path/to/my-tool
```

CLI에 리소스 번들, 동적 라이브러리 또는 헬퍼 실행 파일이 필요한 경우, 배포 디렉터리를 구성하고 해당 디렉터리를 기준으로 진입점을 지정하세요:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

전체 배포 디렉터리가 업로드됩니다. 도구에 필요한 라이브러리, 리소스 및 헬퍼를 포함하고, 빌드 디렉터리 외부에서도 실행될 수 있도록 하세요. 스크립트는 수신자 시스템에 설치된 인터프리터와 shebang이 필요합니다.

## 여러 CLI 타겟 {#multiple-cli-targets}

프리뷰는 하나의 커밋에 대한 동일한 CLI의 빌드를 그룹화합니다. 각 빌드에는 하나의 운영 체제와 하나 이상의 CPU 아키텍처에 대한 배포본이 포함됩니다. 예를 들어, 하나의 프리뷰에는 macOS arm64, macOS x86_64 및 Linux x86_64 배포본이 포함될 수 있습니다. 범용 macOS 실행 파일은 하나의 빌드로 두 Mac 아키텍처를 모두 커버합니다.

각 타겟을 별도로 빌드한 후, 동일한 진입점 기본 이름과 트랙을 사용하여 동일한 Git 체크아웃에서 배포본을 순차적으로 게시하세요:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

이러한 업로드는 동일한 프리뷰 링크에 빌드를 추가합니다. 업로드 간에 프로젝트, 커밋, 게시 계정, CLI 이름 및 트랙을 동일하게 유지하세요. Tuist는 수신자의 운영 체제 및 CPU 아키텍처와 일치하는 빌드를 선택합니다.

## 클라이언트 및 서버 호환성 {#client-and-server-compatibility}

최신 Tuist CLI를 사용하여 데스크톱 및 명령줄 프리뷰를 실행하세요. Tuist를 자체 호스팅하는 경우, 이러한 유형을 게시하기 전에 서버를 업데이트하세요. 모바일 프리뷰는 이전 클라이언트에서도 계속 작동합니다.

수신자의 운영 체제 및 CPU 아키텍처에 맞춰 빌드하세요. Tuist는 앱을 크로스 컴파일하거나 종속성을 설치하지 않으며, Linux 도구도 호환되는 시스템 라이브러리가 필요합니다.

프리뷰는 샌드박스가 아닌 사용자 계정의 권한으로 실행됩니다. 신뢰할 수 있는 작성자와 풀 리퀘스트의 빌드만 실행하세요.

실행 동작 및 인수 전달에 대해서는 <.localized_link href="/guides/features/previews/run/cli">CLI로 프리뷰 실행</.localized_link>을, 접근 권한, 트랙 및 README 배지에 대해서는 <.localized_link href="/guides/features/previews#visibility">프리뷰 개요</.localized_link>를 참조하세요.
