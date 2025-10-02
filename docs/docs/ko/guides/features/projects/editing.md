---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 편집 중 {#편집}

Xcode의 UI를 통해 변경이 이루어지는 기존의 Xcode 프로젝트나 Swift 패키지와 달리, Tuist에서 관리하는 프로젝트는
**매니페스트 파일** 에 포함된 Swift 코드에 정의됩니다. Swift 패키지와 `Package.swift` 파일에 익숙하다면 접근 방식이
매우 유사합니다.

모든 텍스트 편집기를 사용하여 이러한 파일을 편집할 수 있지만, 이를 위해 Tuist에서 제공하는 워크플로( `tuist edit`)를 사용하는
것이 좋습니다. 이 워크플로우는 모든 매니페스트 파일이 포함된 Xcode 프로젝트를 생성하고 이를 편집 및 컴파일할 수 있게 해줍니다.
Xcode를 사용하면 **코드 완성, 구문 강조 표시 및 오류 검사(**)의 모든 이점을 누릴 수 있습니다.

## 프로젝트 편집 {#편집-프로젝트}

프로젝트를 편집하려면 Tuist 프로젝트 디렉토리 또는 하위 디렉토리에서 다음 명령을 실행하면 됩니다:

```bash
tuist edit
```

이 명령은 글로벌 디렉터리에 Xcode 프로젝트를 생성하고 Xcode에서 엽니다. 이 프로젝트에는 모든 매니페스트가 유효한지 확인하기 위해
빌드할 수 있는 `매니페스트` 디렉터리가 포함됩니다.

> [!INFO] 글로브 해결된 매니페스트 `tuist edit` 프로젝트의 루트 디렉토리( `Tuist.swift` 파일이 포함된
> 디렉토리)에서 `**/{Manifest}.swift` 글로브를 사용하여 포함할 매니페스트를 해결합니다. 프로젝트의 루트에 유효한
> `Tuist.swift` 파일이 있는지 확인하세요.

## 워크플로 편집 및 생성 {#edit-and-생성-워크플로}

이미 눈치채셨겠지만, 생성된 Xcode 프로젝트에서는 편집을 수행할 수 없습니다. 이는 생성된 프로젝트가 Tuist에 종속되지 않도록 설계된
것으로, 추후에 Tuist에서 쉽게 이동할 수 있도록 하기 위한 것입니다.

프로젝트를 반복할 때는 터미널 세션에서 `tuist edit` 을 실행하여 Xcode 프로젝트를 가져와 프로젝트를 편집하고, 다른 터미널 세션을
사용하여 `tuist generate` 을 실행하는 것이 좋습니다.
