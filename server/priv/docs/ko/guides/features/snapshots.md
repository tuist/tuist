---
{
  "title": "스냅샷",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Xcode 및 Gradle 프로젝트의 시각적 회귀를 감지합니다. Tuist는 스냅샷 이미지를 저장하고, 각 풀 리퀘스트를 기준 이미지와 비교하며, 대시보드 또는 풀 리퀘스트에서 변경 사항을 승인하거나 거부할 수 있게 해줍니다."
}
---
# 스냅샷 {#snapshots}

> [!IMPORTANT]
> **초대 전용**
>
> 스냅샷은 현재 초대 전용입니다. 계정 액세스를 요청하려면 [문의](mailto:contact@tuist.dev)하거나 [커뮤니티 Slack](https://slack.tuist.dev)에서 알려주세요.

스냅샷 테스트는 UI를 이미지로 렌더링하고 참조 이미지와 비교하여 시각적 회귀를 감지합니다. 이러한 참조 이미지를 리포지토리에 커밋하는 대신, 각 테스트 실행이 렌더링한 이미지를 Tuist에 업로드하세요. Tuist는 이를 **기준선**과 비교하고 대시보드에서 변경 사항을 표시하며, 누군가 변경 사항을 승인할 때까지 실행을 실패 처리합니다.

- Git에 참조 이미지가 없으므로 체크아웃 용량이 작게 유지되고 PNG 파일에서 충돌을 해결할 필요가 없습니다.
- 검토자는 코드 옆에서 변경 사항을 확인할 수 있습니다: 나란히 보기, diff 보기, 와이프 또는 어니언 스킨 오버레이 보기.
- 변경 사항은 대시보드 또는 풀 리퀘스트에서 승인되거나 거부되며, 브랜치가 병합되면 승인이 새로운 기준선이 됩니다.

## 작동 방식 {#how-it-works}

1. 테스트는 예를 들어 모든 SwiftUI 또는 Compose 미리보기의 이미지를 렌더링합니다.
2. Tuist CLI 또는 Gradle 플러그인은 이를 현재 커밋의 **스냅샷 빌드**로 업로드합니다.
3. Tuist는 기준선을 선택합니다: 브랜치가 시작된 커밋 시점의 기본 브랜치 빌드입니다.
4. 각 이미지는 기준선과 비교되어 변경됨, 추가됨, 제거됨, 또는 변경 없음으로 표시됩니다.
5. 빌드는 다음과 같은 판정을 받습니다:

| 판정 | 실행 | 조건 |
| --- | --- | --- |
| 기준선 | 통과 | 빌드가 기본 브랜치에서 왔으므로 이후 빌드는 이와 비교됩니다. |
| 통과됨 | 통과 | 이미지가 변경되거나 제거되지 않았습니다. 새 이미지는 검토가 필요하지 않습니다. |
| 검토 필요 | 실패 | 이미지가 변경되거나 제거되었으며 아직 아무도 검토하지 않았습니다. |
| 승인됨 | 통과 | 누군가 변경 사항을 승인했습니다. |
| 거부됨 | 실패 | 누군가 변경 사항을 거부했습니다. |

빌드는 **세트**(예: `ios-iphone`, `android-phone`) 내에서 비교됩니다. 서로 다른 크기로 렌더링된 이미지가 비교되지 않도록 장치 구성당 하나의 세트를 사용하세요.

## 설정 {#set-up}

프로젝트에 맞는 통합 방식을 선택하세요:

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test로 Xcode 프로젝트의 모든 SwiftUI 미리보기를 스냅샷으로 저장합니다."
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="tuist test로 Tuist가 생성한 프로젝트의 모든 SwiftUI 미리보기를 스냅샷으로 저장합니다."
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle 플러그인으로 모든 Compose 미리보기를 스냅샷으로 저장하거나 Paparazzi 및 Roborazzi가 기록한 내용을 업로드합니다."
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## 대시보드에서 변경 사항 검토 {#dashboard}

모든 스냅샷 빌드는 프로젝트 대시보드의 **Tests → Snapshots** 아래에 페이지를 가집니다. 이 페이지는 빌드의 판정, 브랜치, 커밋, 풀 리퀘스트 및 기준선을 표시하고 이미지를 상태와 그룹별로 나열합니다. **Approve changes** 또는 **Reject changes**를 사용하여 빌드를 검토하세요. 나중에 검토 결과를 변경할 수 있습니다.

![변경된 이미지가 기준선과 나란히 표시되어 검토가 필요한 스냅샷 빌드](/images/guides/features/snapshots/review.png)

**Side by side**, 변경된 픽셀을 강조하는 **Diff**, 기준선과 새 이미지 사이를 슬라이드하는 **Wipe**, 그리고 한 이미지를 다른 이미지로 페이드 인하는 **Onion** 모드를 전환할 수 있습니다. 각 이미지는 전체 화면으로 열 수 있습니다.

![기준선과 새 이미지 사이를 슬라이드하는 와이프 모드](/images/guides/features/snapshots/wipe.png)

## 풀 리퀘스트에서 변경 사항 검토 {#pull-request}

<.localized_link href="/guides/integrations/gitforge/github">GitHub 앱</.localized_link>이 설치되면 풀 리퀘스트의 모든 스냅샷 빌드에 `tuist/snapshots (<set>)`라는 검사가 추가됩니다. 변경 사항에 대한 검토가 필요하거나 검토자가 거부한 경우, 검사는 실패하며 필수 설정 시 병합을 차단합니다:

![변경 사항이 거부되어 스냅샷 검사가 실패한 풀 리퀘스트의 병합 박스](/images/guides/features/snapshots/github-pr-checks.png)

이 검사는 세트에서 변경, 추가 및 제거된 이미지의 수를 계산하고 대시보드의 빌드로 연결됩니다. GitHub를 떠나지 않고 검사 페이지에서 변경 사항을 승인하거나 거부할 수 있습니다. 검사는 검토자의 이름으로 업데이트되며, 거부된 빌드도 나중에 승인할 수 있습니다.

![변경 사항이 거부된 후 GitHub의 스냅샷 검사로, 승인 버튼이 표시됨](/images/guides/features/snapshots/github-check-run.png)

승인한다고 테스트가 다시 실행되지는 않습니다: 검사를 통과시킬 뿐입니다. 동일한 브랜치의 이후 빌드는 정확히 동일한 변경 사항을 가진 한 승인을 유지하므로, CI를 다시 실행하거나 검토된 이미지에 영향을 주지 않는 커밋을 푸시해도 통과합니다. 이미지의 다른 변경 사항은 새로운 검토가 필요합니다. 브랜치가 병합되면 기본 브랜치의 빌드가 새로운 기준선이 됩니다.
