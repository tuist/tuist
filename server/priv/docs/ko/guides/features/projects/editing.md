---
{
  "title": "편집",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Xcode 자동 완성 및 빌드 검증 기능을 활용해 Tuist 프로젝트 매니페스트를 편집합니다."
}
---
# 편집하기 {#editing}

Xcode의 UI를 통해 변경하는 기존 Xcode 프로젝트나 Swift Package와 달리, Tuist로 관리되는 프로젝트는 **매니페스트 파일**에 포함된 Swift 코드로 정의됩니다. Swift Package와 `Package.swift` 파일에 익숙하다면 접근 방식이 매우 유사합니다.

텍스트 편집기로 이 파일들을 편집할 수 있지만, Tuist가 제공하는 워크플로우인 `tuist edit`를 사용하는 것을 권장합니다. 이 워크플로우는 모든 매니페스트 파일을 포함하는 Xcode 프로젝트를 생성하고, 이를 편집하고 컴파일할 수 있게 해줍니다. Xcode를 사용함으로써 **코드 자동 완성, 구문 강조, 오류 검사**의 모든 이점을 누릴 수 있습니다.

## 프로젝트 편집하기 {#edit-the-project}

프로젝트를 편집하려면 Tuist 프로젝트 디렉터리 또는 하위 디렉터리에서 다음 명령어를 실행하세요:

```bash
tuist edit
```

이 명령어는 전역 디렉터리에 Xcode 프로젝트를 생성하고 Xcode에서 엽니다. 프로젝트에는 모든 매니페스트가 유효한지 확인하기 위해 빌드할 수 있는 `Manifests` 디렉터리가 포함되어 있습니다.

> [!NOTE]
> **Glob으로 해결된 매니페스트**
>
> `tuist edit`는 프로젝트 루트 디렉터리(`Tuist.swift` 파일이 있는 디렉터리)에서 `**/{Manifest}.swift` glob 패턴을 사용하여 포함할 매니페스트를 해결합니다. 프로젝트 루트에 유효한 `Tuist.swift`가 있는지 확인하세요.


### 매니페스트 파일 무시하기 {#ignoring-manifest-files}

프로젝트의 하위 디렉터리에 실제 Tuist 매니페스트가 아닌 매니페스트 파일과 동일한 이름(예: `Project.swift`)의 Swift 파일이 포함된 경우, 프로젝트 루트에 `.tuistignore` 파일을 생성하여 편집 프로젝트에서 제외할 수 있습니다.

`.tuistignore` 파일은 glob 패턴을 사용하여 무시할 파일을 지정합니다:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

이는 테스트 픽스처나 예제 코드가 우연히 Tuist 매니페스트 파일과 동일한 명명 규칙을 사용하는 경우에 특히 유용합니다.

## 편집 및 생성 워크플로우 {#edit-and-generate-workflow}

알아차렸겠지만, 편집은 생성된 Xcode 프로젝트에서 수행할 수 없습니다. 이는 생성된 프로젝트가 Tuist에 의존하지 않도록 설계된 것으로, 향후 Tuist에서 쉽게 전환할 수 있도록 하기 위함입니다.

프로젝트를 반복 작업할 때는 터미널 세션에서 `tuist edit`를 실행하여 프로젝트를 편집할 Xcode 프로젝트를 얻고, 다른 터미널 세션에서 `tuist generate`를 실행하는 것을 권장합니다.
