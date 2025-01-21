---
title: Xcode project
titleTemplate: :title · Registry · Develop · Guides · Tuist
description: Learn how to use the Tuist Registry in an Xcode project.
---

# Xcode project {#xcode-project}

To add packages using the registry in your Xcode project, use the default Xcode UI. Xcode의 `Package Dependencies` 탭에서 `+` 버튼을 눌러서 레지스트리에 패키지를 검색할 수 있습니다. 패키지가 레지스트리에 사용가능하면 우측 상단에 `tuist.dev` 레지스트리가 표시됩니다:

![패키지 의존성 추가](/images/guides/develop/build/registry/registry-add-package.png)

> [!NOTE]
> Xcode currently doesn't support automatically replacing source control packages with their registry equivalents. 처리 속도를 높이려면 소스 제어 패키지를 삭제하고 레지스트리 패키지를 추가해야 합니다.
