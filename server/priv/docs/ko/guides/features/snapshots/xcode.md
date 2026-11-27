---
{
  "title": "Xcode",
  "titleTemplate": ":title · 스냅샷 · 기능 · 가이드 · Tuist",
  "description": "Xcode 프로젝트의 모든 SwiftUI 프리뷰를 스냅샷으로 저장하고 Tuist에서 변경 사항을 검토하세요."
}
---
# Xcode 스냅샷 {#xcode-snapshots}

> [!IMPORTANT]
> **요구 사항**
>
> - 계정에 스냅샷 기능이 활성화되어 있어야 합니다. 현재 초대 전용으로 제공되며, 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.
> - Tuist에 <.localized_link href="/guides/get-started/existing-xcode-project">연결된</.localized_link> 프로젝트.
> - 프리뷰를 렌더링하려면 iOS 17 또는 macOS 14가 필요합니다.

[tuist/snapshots](https://github.com/tuist/snapshots) 라이브러리는 앱의 모든 SwiftUI 프리뷰를 이미지로 렌더링하므로 스냅샷 테스트를 직접 작성할 필요가 없습니다. `tuist xcodebuild test`는 실행 후 이미지를 업로드하며, Tuist는 이를 <.localized_link href="/guides/features/snapshots#how-it-works">기준선</.localized_link>과 비교합니다.

## 설정하기 {#set-up}

1. Xcode에서 버전 `0.1.0`부터 `https://github.com/tuist/snapshots` 패키지를 추가하세요.
2. 앱이 호스팅하는 단위 테스트 타겟(예: `AppSnapshotTests`)을 생성하고, 패키지의 `TuistSnapshotsTesting` 제품을 해당 타겟에 연결하세요.
3. 해당 타겟에 테스트 클래스를 추가하세요. 각 프리뷰는 자체 테스트가 됩니다:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. 타겟을 실행하는 스킴(예: `AppSnapshots`)을 추가하세요. 이 스킴은 스냅샷 세트의 이름이 됩니다.

## 실행하기 {#run}

`tuist xcodebuild test`를 통해 테스트를 실행하세요. 다른 기기는 크기가 다른 이미지를 렌더링하므로 항상 동일한 시뮬레이터에서 실행해야 합니다:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI 환경에서는 테스트가 렌더링한 이미지가 실행 후 업로드되며, 이미지가 변경되었고 아무도 변경 사항을 승인하지 않은 경우 명령이 실패합니다. 로컬 실행은 커밋되지 않은 변경 사항을 업로드할 수 있으므로 아무것도 업로드하지 않습니다.

<!-- @snippet: ./_previews-library -->
