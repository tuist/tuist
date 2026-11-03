---
{
  "title": "Once 아티팩트 게시",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "명시적인 대상 승인을 통해 기존 Tuist 프로젝트에 변경 불가능한 Once 애플리케이션 아티팩트를 게시합니다."
}
---
# Once 아티팩트 게시

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews)는 기존 Tuist 인증을 사용하여 불변 아티팩트를 게시할 수 있습니다. 이를 위해서는 Once 0.74.0 이상과 아티팩트 수신기가 구성된 Tuist 서버가 필요합니다. Once 0.73.x는 대신 레거시 단일 페이로드 어댑터를 사용합니다.

## 대상 구성

워크스페이스의 `once.toml`에서:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

수신기는 알 수 없는 인터페이스를 포함하여 전체 세트, 멤버 매니페스트 및 페이로드를 보관합니다. 지원되는 네이티브 인터페이스는 프로젝트의 기본 가시성, 액세스 및 배포 설정을 사용하여 비동기적으로 미리보기로 프로젝션됩니다. 일반 아티팩트 콘텐츠는 공개 프로젝트에서도 비공개로 유지됩니다. 영수증은 아티팩트 저장을 확인하지만 미리보기 처리 완료를 의미하지는 않으며, 해당 URL은 프로젝트의 미리보기 목록을 엽니다.

## 적격 애플리케이션

Apple 프로젝션은 macOS에서 내보낸 임시 서명된 macOS 및 시뮬레이터 애플리케이션에 대해 `dev.once.apple-install.v2` 메타데이터를 허용합니다. 실제 기기용 애플리케이션은 대상에서 제외됩니다. Android 프로젝션은 검증된 서명이 포함된 `dev.once.android-install.v1` 메타데이터를 허용합니다. Once는 디버그 서명된 비계측 APK에 대해서만 자동 게시를 승인합니다. 알 수 없는 인터페이스는 미리보기 생성 없이 아티팩트로 다운로드할 수 있는 상태로 유지됩니다. Android 설치 링크는 페이로드가 콘텐츠 다이제스트 아래에 저장되더라도 `.apk` 파일 이름을 유지합니다.

## 빌드 후 게시 옵트인

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

요청된 모든 빌드는 성공해야 합니다. 자동 게시에는 또한 전체 클로저에 대한 프로듀서 승인 및 이 머신, 워크스페이스, 정확한 엔드포인트, 타겟 및 안정적인 Tuist 프로젝트 대상에 대한 로컬 권한이 필요합니다. 정책이나 권한이 없으면 아티팩트 게시 네트워크 요청이 발생하지 않습니다. 일반적인 Once 빌드는 암시적 게시 부작용으로부터 자유롭습니다.

동일한 보존된 게시를 다시 실행하면 원격 영수증을 확인하고 추가 업로드를 방지합니다. 이는 `tuist share`의 중복 빌드 동작과 다릅니다.

## 보존

호스팅된 Tuist에서는 아티팩트 게시가 30일 후에 만료됩니다. 자체 호스팅 인스턴스는 `TUIST_APP_PREVIEW_RETENTION_DAYS`을 사용하며, 이를 설정하지 않으면 이 계열의 만료가 비활성화됩니다. 만료된 기록은 무덤 표시(tombstone)로 남으며 동일한 의도를 다시 실행해도 재활성화할 수 없습니다. 기존 `tuist share` 서명, 가시성 및 배포 워크플로는 변경되지 않습니다.

게시된 빌드 실행, 액세스, 트랙 및 README 배지에 대해서는 <.localized_link href="/guides/features/previews#run-a-preview">미리보기 실행</.localized_link>을 참조하세요.

## Apple 미리보기

적격한 Apple 시뮬레이터 및 macOS 미리보기에 대해서는 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 동반 앱 지침</.localized_link>을 참조하세요. 실제 기기용 애플리케이션은 Once 게시 대상에서 계속 제외됩니다.
