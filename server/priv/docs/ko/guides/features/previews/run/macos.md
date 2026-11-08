---
{
  "title": "macOS 앱으로 미리보기 실행하기",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist macOS 메뉴 바 앱을 사용하여 호환되는 Apple 미리보기를 기기와 시뮬레이터에서 실행하세요."
}
---
# macOS 앱으로 미리보기 실행

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple 미리보기의 경우, 빌드가 Xcode, Bazel 또는 Once에서 생성되었는지 여부와 관계없이 Tuist macOS 메뉴 바 앱은 CLI의 대안입니다. 게시 워크플로의 서명 및 자격 요건은 여전히 적용됩니다.

## 설치 {#install}

[앱 다운로드](https://tuist.dev/download)하거나 `brew install --cask tuist/tuist/tuist`로 설치하세요.

## 빌드 실행 {#run-a-build}

메뉴 바 앱에서 호환되는 기기 또는 시뮬레이터를 선택한 후, 미리보기 페이지에서 **실행**을 클릭하세요.

macOS 앱은 먼저 앱별로 최신 호환 미리보기를 요청합니다. 플랫폼 필터를 적용하기 전에 개별 앱을 선택하는 이전 서버에서는 사용 가능한 빌드를 숨길 수 있는 차단 없이 페이지네이션된 기록으로 대체됩니다.

접근 권한 및 조직 관리는 <.localized_link href="/guides/features/previews#visibility">공개 범위와 트랙</.localized_link>을 참조하세요.
