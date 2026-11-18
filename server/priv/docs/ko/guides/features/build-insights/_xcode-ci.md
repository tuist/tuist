## CI에서 빌드 인사이트 {#continuous-integration}

CI에서 빌드 인사이트를 추적하려면 CI가 <.localized_link href="/guides/server/authentication#continuous-integration">인증</.localized_link>되었는지 확인하세요.

Xcodebuild 기반 CI에서는 다음이 필요합니다:
- `xcodebuild` 액션을 호출할 때 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>을 사용하세요.
- `xcodebuild` 명령에 `-resultBundlePath`을 추가하세요.

`-resultBundlePath`이 없으면 필요한 활동 로그와 결과 번들이 생성되지 않으며 `tuist inspect build`이 빌드를 분석할 수 없습니다.
