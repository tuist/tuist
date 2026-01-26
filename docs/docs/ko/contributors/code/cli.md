---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Source:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
and
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 용도 {#what-it-is-for}

CLI는 Tuist의 핵심입니다. 프로젝트 생성, 자동화 워크플로(테스트, 실행, 그래프, 검사)를 처리하며, 인증, 캐시, 인사이트,
미리보기, 레지스트리, 선택적 테스트와 같은 기능을 위해 Tuist 서버와의 인터페이스를 제공합니다.

## 기여 방법 {#how-to-contribute}

### 요구사항 {#requirements}

- macOS 14.0 이상 버전
- Xcode 26+

### 로컬 환경 설정 {#set-up-locally}

- `git clone git@github.com:tuist/tuist.git`로 소스를 받으세요
- Mise는 [공식 설치 스크립트](https://mise.jdx.dev/getting-started.html) (Homebrew 아님)을
  사용해 설치하고 `mise install을 실행하세요.`
- Tuist 의존성 설치: `tuist install`
- 워크스페이스 생성: `tuist generate`

생성된 프로젝트가 자동으로 열립니다. 나중에 다시 열어야 할 경우, `open Tuist.xcworkspace` 를 실행하세요.

::: XED 관련 .
<!-- -->
`xed.` 로 프로젝트를 열려고 하면 패키지가 열리고 Tuist 생성 작업공간이 열리지 않습니다. `Tuist.xcworkspace` 를
사용하세요.
<!-- -->
:::

### Tuist 실행 {#run-tuist}

#### Xcode에서 {#from-xcode}

`tuist` scheme을 편집하고 `generate --no-open` 와 같은 인수를 설정하세요. 작업 디렉터리를 프로젝트 루트로
설정하거나 (또는 `--path` 를 사용하세요).

::: 경고 PROJECTDESCRIPTION 컴파일
<!-- -->
CLI는 `ProjectDescription` 빌드에 의존합니다. 실행에 실패할 경우, 먼저 `Tuist-Workspace` scheme을
빌드하십시오.
<!-- -->
:::

#### 터미널에서 {#from-the-terminal}

먼저 작업 공간을 생성하세요:

```bash
tuist generate --no-open
```

그런 다음 Xcode로 `tuist` 실행 파일을 빌드하고 DerivedData에서 실행하세요:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

또는 Swift Package Manager를 통해:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
