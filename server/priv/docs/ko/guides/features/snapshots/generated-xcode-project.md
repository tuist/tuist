---
{
  "title": "생성된 Xcode 프로젝트",
  "titleTemplate": ":title · 스냅샷 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 생성한 프로젝트의 모든 SwiftUI 프리뷰를 스냅샷으로 저장하고 Tuist에서 변경 사항을 검토하세요."
}
---
# 생성된 Xcode 프로젝트 스냅샷 {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **요구 사항**
>
> - 계정에 스냅샷 기능이 활성화되어 있어야 합니다. 현재는 초대 전용으로, 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요.
> - Tuist에 <.localized_link href="/guides/get-started/generated-xcode-project">연결된</.localized_link> 프로젝트.
> - 프리뷰를 렌더링하려면 iOS 17 또는 macOS 14가 필요합니다.

[tuist/snapshots](https://github.com/tuist/snapshots) 라이브러리는 앱의 모든 SwiftUI 프리뷰를 이미지로 렌더링하므로 스냅샷 테스트를 수동으로 작성할 필요가 없습니다. `tuist test`는 실행 후 이미지를 업로드하며, Tuist는 이를 <.localized_link href="/guides/features/snapshots#how-it-works">기준선</.localized_link>과 비교합니다.

## 설정하기 {#set-up}

패키지를 `Tuist/Package.swift`에 추가하세요:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

그런 다음 앱과 `TuistSnapshotsTesting`에 의존하는 단위 테스트 타겟과 이를 실행하는 스킴을 추가하세요. 스킴은 스냅샷 세트의 이름을 지정합니다:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

타겟에 테스트 클래스를 추가하세요. 각 프리뷰는 자체 테스트가 됩니다:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

패키지를 가져오려면 `tuist install`를 실행하세요.

## 실행하기 {#run}

`tuist test`로 스킴을 실행하세요. 항상 동일한 시뮬레이터에서 실행해야 합니다. 다른 장치는 다른 크기의 이미지를 렌더링하기 때문입니다:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

CI에서는 테스트가 렌더링한 이미지가 실행 후 업로드되며, 이미지가 변경되었고 아무도 변경 사항을 승인하지 않으면 명령이 실패합니다. 로컬 실행은 커밋되지 않은 변경 사항을 업로드하게 되므로 아무것도 업로드하지 않습니다.

> [!TIP]
> <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>을 사용하면 스냅샷 테스트 타겟은 이미지가 통과하거나 승인된 경우에만 건너뛰어지므로, 아무도 검토하지 않은 변경 사항이 있는 타겟을 재실행에서 건너뛰지 않습니다. 실행이 타겟을 건너뛰면 렌더링되지 않은 이미지는 제거된 것이 아닌 건너뜀으로 처리됩니다.

<!-- @snippet: ./_previews-library -->
