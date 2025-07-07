---
title: Editing
titleTemplate: :title · Projects · Features · Guides · Tuist
description: Xcode의 빌드 시스템과 편집기 기능을 활용하여 프로젝트를 선언하기 위한 Tuist의 편집 워크플로우에 대해 배워봅니다.
---

# Editing {#editing}

Xcode의 UI를 통해 변경되는 기존 Xcode 프로젝트와 Swift Package와 달리, Tuist로 관리되는 프로젝트는 매니페스트 파일에 포함된 Swift 코드로 정의됩니다.
Swift Package와 `Package.swift` 파일에 익숙하다면, 이 방식은 매우 유사합니다.

어떤 편집기로도 이 파일을 수정할 수 있지만, 우리는 Tuist에서 제공하는 워크플로우인 `tuist edit`를 사용하길 권장합니다.
이 워크플로우는 모든 매니페스트 파일을 포함하는 Xcode 프로젝트를 생성하고 이를 수정하고 컴파일 할 수 있도록 합니다.
Xcode를 사용하면 **코드 완성, 구문 강조, 그리고 오류 검사**의 모든 이점을 얻을 수 있습니다.

## 프로젝트 수정하기 {#edit-the-project}

프로젝트를 수정하려면 Tuist 프로젝트 디렉토리 또는 그 하위 디렉토리에서 다음의 명령어를 수행해야 합니다:

```bash
tuist edit
```

이 명령어는 전역 디렉토리에 Xcode 프로젝트를 생성하고 Xcode에서 이 프로젝트를 엽니다.
프로젝트는 모든 매니페스트가 유효한지 확인하기 위해 빌드 할 수 있는 `Manifests` 디렉토리를 포함합니다.

> [!INFO] GLOB-RESOLVED MANIFESTS\
> `tuist edit`는 프로젝트의 루트 디렉토리 (`Tuist.swift` 파일을 포함하는 디렉토리) 에서 glob `**/{Manifest}.swift`를 사용하여 포함될 매니페스트를 해결합니다. 프로젝트 루트에 유효한 `Tuist.swift`가 있는지 확인해야 합니다.

## 워크플로우 수정과 생성 {#edit-and-generate-workflow}

이미 알고 있듯이, 이미 생성된 Xcode 프로젝트는 편집이 불가능 합니다.
이것은 생성된 프로젝트가 Tuist에 의존 하지 않도록 설계되어 있으며, 나중에 Tuist를 쉽게 걷어낼 수 있도록 합니다.

프로젝트를 반복적으로 수정할 때, 터미널 세션에서 `tuist edit`를 수행하여 편집할 수 있는 Xcode 프로젝트를 열고, 다른 터미널 세션에서 `tuist generate`를 수행하길 권장합니다.
