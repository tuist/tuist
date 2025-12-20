---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode 프로젝트 {#xcode-project}

Xcode 프로젝트에서 레지스트리를 사용하여 패키지를 추가하려면 기본 Xcode UI를 사용합니다. Xcode의 `패키지 종속성` 탭에서 `+`
버튼을 클릭하여 레지스트리에서 패키지를 검색할 수 있습니다. 레지스트리에서 패키지를 사용할 수 있는 경우 오른쪽 상단에 `tuist.dev`
레지스트리가 표시됩니다:

![패키지 종속성 추가](/images/guides/features/build/registry/registry-add-package.png)

::: info Mise란?
<!-- -->
Xcode는 현재 소스 제어 패키지를 레지스트리에 해당하는 패키지로 자동 대체하는 기능을 지원하지 않습니다. 해결 속도를 높이려면 소스 제어
패키지를 수동으로 제거하고 레지스트리 패키지를 추가해야 합니다.
<!-- -->
:::
