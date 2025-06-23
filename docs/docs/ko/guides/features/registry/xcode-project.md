---
title: Xcode project
titleTemplate: :title · Registry · Develop · Guides · Tuist
description: Xcode 프로젝트에서 Tuist Registry를 사용하는 방법을 배워봅니다.
---

# Xcode project {#xcode-project}

Xcode 프로젝트에서 레지스트리를 사용하여 패키지를 추가하려면, 기본 Xcode UI를 사용합니다. Xcode의 `Package Dependencies` 탭에서 `+` 버튼을 눌러서 레지스트리에 패키지를 검색할 수 있습니다. 패키지가 레지스트리에 사용가능하면 우측 상단에 `tuist.dev` 레지스트리가 표시됩니다:

![패키지 의존성 추가](/images/guides/features/build/registry/registry-add-package.png)

> [!NOTE]\
> Xcode는 현재 소스 제어 패키지를 레지스트리로 자동으로 대체하는 기능을 지원하지 않습니다. 처리 속도를 높이려면 소스 제어 패키지를 삭제하고 레지스트리 패키지를 추가해야 합니다.
