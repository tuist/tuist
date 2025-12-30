---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 편집 {#editing}

Xcode의 UI를 통해서 모든 변경 사항이 이루어지는 기본 Xcode 프로젝트나 Swift 패키지와는 다르게, , Tuist로 관리되는
프로젝트들은 **Manifest 파일들**에 들어있는 Swift 코드로 정의 됩니다. 만약 Swift 패키지와 `Package.swift`
파일에 익숙하다면, Tuist의 방식도 유사 합니다.

이 파일들은 어떤 편집기로도 수정할 수 있지만, Tuist가 제공하는 방법인 `tuist edit`의 사용하는 것을 권장 합니다. 이 과정은
모든 Manifest 파일들을 가진 Xcode 프로젝트를 생성하고 편집 및 컴파일 할 수 있게 해줍니다. Xcode 덕분에, 여러분은 **코드
완성, 문법 강조, 그리고 오류 확인** 등의 모든 편의 기능을 사용할 수 있습니다.

## 프로젝트 편집 {#edit-the-project}

프로젝트를 편집하기 위해, Tuist 프로젝트 디렉토리나 하위 디렉토리에서 다 명령어를 사용할 수 있습니다:

```bash
tuist edit
```

이 명령어는 전역 디렉토리에 Xcode 프로젝트를 생성하고 Xcode에서 엽니다. 생성된 프로젝트는 모든 Manifest가 유효한 것을 보장하기
위해 빌드 할 수 있는 `Manifests` 디렉토리를 가집니다.

::: info Glob으로 처리된 Manifest
<!-- -->
`tuist edit` 는 최상위(유일하게 `Tuist.swift` 파일을 가지는) 디렉토리에서 `**/{Manifest}.swift`
Glob을 사용해서 Manifest들을 처리 합니다. 최상위 디렉토리에 올바른 `Tuist.swift`가 있는지 확인하세요.
<!-- -->
:::

### Manifest 파일 무시하기 {#ignoring-manifest-files}

만약 프로젝트가 실제로 Tuist Manifest는 아니지만 Manifest 파일들과 같은 이름의 Swift 파일들을 하위 디렉토리에
가진다면(예를 들어, `Project.swift`), 프로젝트 수정에서 제외하기 위해 `.tuistignore` 를 최상위에 만들 수 있습니다.

`.tuistignore` 파일은 어떤 파일이 무시 되어야 하는지 지정하기 위해 Glob 패턴을 사용합니다:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

이것은 특히 Tuist Manifest 파일들과 같은 작명 규칙을 사용하는 test fixtures를 가지거나 예제 코드를 가졌을 때 유용
합니다.

## 수정과 생성 과정 {#edit-and-generate-workflow}

보셔셔 아시겠지만, 생성된 Xcode 프로젝트에서는 수정할 수 없습니다. 여러분이 미래에 적은 노력으로도 Tuist에서 (다른 것으로)전환할 수
있도록, 생성된 프로젝트가 Tuist에 의존하지 않게 한 설계 입니다.

프로젝트를 반복할 때, 한 터미널에서는 Xcode 프로젝트를 수정하기 위해 `tuist edit` 를, 다른 터미널에서는 `tuist
generate`를 실행하는 것을 권장합니다.
