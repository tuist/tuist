---
{
  "title": "Xcode 미리보기",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "기존 Xcode 프로젝트와 Tuist로 생성된 프로젝트에서 애플리케이션 미리보기를 공유하세요."
}
---
# Xcode 미리보기

애플리케이션을 빌드한 후 `tuist share`를 사용하여 Tuist 프로젝트에 게시하세요. 먼저 <.localized_link href="/guides/get-started/existing-xcode-project">기존 Xcode 프로젝트</.localized_link> 또는 <.localized_link href="/guides/get-started/generated-xcode-project">생성된 프로젝트</.localized_link> 가이드를 따라 프로젝트를 연결하세요.

## 빌드 및 공유

Tuist가 생성한 프로젝트의 경우:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

기존 Xcode 프로젝트의 경우:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

스킴, 프로젝트, 워크스페이스 이름을 자신의 것으로 바꾸세요. Release 빌드를 공유하려면 빌드 시 `-configuration Release`를 사용하고 공유 시 `--configuration Release`를 사용하세요.

## 실제 기기

수신자의 기기에 설치할 수 있는 프로비저닝 프로필로 기기용 빌드에 서명하는 책임은 귀하에게 있습니다. 시뮬레이터 SDK 대신 기기 대상(destination)으로 빌드하세요:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

이미 내보낸 IPA도 공유할 수 있습니다:

```bash
tuist share App.ipa
```

수신자는 모바일 기기에서 IPA 미리보기 링크를 열어 애플리케이션을 설치할 수 있습니다. 인증과 프로젝트의 미리보기 공개 설정은 여전히 적용됩니다.

## CI 및 빌드 번호

기존 <.localized_link href="/guides/integrations/continuous-integration">CI 인증</.localized_link>을 사용하고 각 새 빌드마다 `CFBundleVersion`를 고유하게 만드세요. 예를 들어 GitHub Actions의 <code v-pre>${{ github.run_number }}</code>를 사용하세요. `tuist share`를 통해 동일한 바이너리와 빌드 번호를 다시 업로드하면 중복이 생성되지 않고 실패합니다.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

게시된 빌드 실행, 접근 권한, 트랙, README 배지에 대해서는 <.localized_link href="/guides/features/previews#run-a-preview">미리보기 실행</.localized_link>을 참조하세요.

<!-- @snippet: ./_tuist-share -->

수신자는 빌드 시스템 통합과 무관하게 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 앱</.localized_link> 또는 <.localized_link href="/guides/features/previews/run/ios">iPhone 앱</.localized_link>을 사용할 수 있습니다. iPhone 가이드에는 Tuist SDK를 사용한 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">인앱 업데이트 알림</.localized_link>도 포함되어 있습니다.
