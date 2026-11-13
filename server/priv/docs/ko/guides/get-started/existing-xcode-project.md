---
{
  "title": "Xcode 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "기존 Xcode 프로젝트를 Tuist에 연결하여 Xcode 컴파일 캐시, 빌드 및 테스트 인사이트, 번들 크기 추적, 미리보기 링크를 활용하세요. 프로젝트 생성을 도입하지 않아도 됩니다."
}
---
# Xcode 프로젝트 {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

`.xcodeproj` 또는 `.xcworkspace`를 그대로 유지하면서 프로젝트 생성을 채택하지 않고 Tuist의 기능을 활용하려는 경우 이 경로를 따르세요. 아래 각 섹션은 현재 누락된 부분을 설명하고, 그 격차를 채워주는 기능을 안내합니다.

## 필수 조건

- **Xcode 26 이상**이 설치된 macOS(컴파일레이션 캐시와 최신 인사이트는 이에 의존합니다).
- <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스</.localized_link>.

## 프로젝트 연결

저장소 루트에서 `tuist init`를 실행하세요. Tuist가 워크스페이스를 감지하면 **`<YourApp>` 통합**을 선택한 후, 브라우저에서 인증하고 프로젝트를 소유할 계정을 선택하세요. Tuist는 루트에 `Tuist.swift`를 작성하여 프로젝트 핸들을 고정하므로 팀원과 CI가 동일한 연결을 공유합니다. 이를 커밋하세요.

코딩 에이전트나 스크립트로 이를 수행하는 경우, 먼저 `tuist auth login`를 실행하세요(브라우저 흐름은 Enter 키를 누를 때까지 대기합니다). 그런 다음 비대화형 형식을 사용하세요:

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

아래 내용은 모두 선택 사항이며 독립적입니다.

## Xcode 컴파일레이션 캐시

Xcode 26은 파일별 컴파일레이션 캐시를 제공하지만, 해당 저장소는 머신의 `DerivedData` 내부에 있습니다. 클린 빌드는 로컬에 이를 채우지만, 팀원과 CI 러너는 해당 저장소를 볼 수 없으므로 처음부터 다시 빌드합니다.

`tuist setup cache`는 Xcode의 컴파일레이션 캐시를 공유 Tuist 캐시 네트워크로 지정합니다. 개발자 머신이나 CI 실행 중 하나에서 캐시 히트가 발생하면 동일한 리비전을 빌드하는 다른 모든 머신이 혜택을 받습니다.

```bash
tuist setup cache
```

이 명령은 공유 캐시를 사용하기 위해 Xcode가 필요로 하는 빌드 설정을 출력합니다. 프로젝트를 수정하지 않으므로, <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">Xcode 빌드 설정 구성</.localized_link>에 설명된 대로 프로젝트의 빌드 설정이나 `.xcconfig` 파일에 추가하세요.

Xcode에서 빌드한 후, 두 번째 머신이나 CI 러너에서 동일한 리비전을 빌드하세요. 두 번째 빌드는 훨씬 짧은 시간 내에 완료되며, Xcode의 빌드 보고서에 컴파일레이션 캐시 히트가 표시됩니다.

## 빌드 인사이트

Xcode는 로그와 빌드 보고서에 타겟별 빌드 소요 시간을 기록합니다. 하지만 실행 간 또는 머신 간으로 집계되지 않습니다. 한 PR에 포함된 빌드 시간 회귀는 일반적으로 전체 CI 속도 저하로만 나타나며, 어떤 타겟이 원인인지 또는 언제 발생했는지에 대한 명확한 신호는 없습니다.

빌드 인사이트는 모든 빌드의 소요 시간과 단계별 타이밍을 기록하므로 대시보드에서 추세를 확인할 수 있습니다. 스키마에 단일 행의 사후 작업을 추가하면 됩니다:

1. Xcode에서: **Product → Scheme → Edit Scheme…**
2. **Build → Post-actions**을 확장하고, **+** 를 클릭한 후, **New Run Script Action**을 선택하세요.
3. **Provide build settings from**에서 앱 타겟을 선택하세요.
4. Tuist 설치 방식에 맞는 행을 붙여넣으세요: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode의 스키마 스크립트는 셸의 `PATH`를 상속받지 않으므로 mise의 심이 자동으로 발견되지 않습니다. 위의 Mise 행은 절대 경로로 mise를 호출하고 `$SRCROOT`에서 구성을 로드하도록 요청하여 프로젝트에 고정된 버전을 선택합니다.
5. 한 번 빌드하세요. 빌드가 몇 초 이내에 대시보드의 **Builds** 탭에 나타납니다.

## 테스트 인사이트

Xcode의 테스트 로그는 한 번의 실행마다 테스트별 결과를 나열합니다. 실제로 필요한 교차 실행 신호(테스트 실패 빈도, 지난주보다 얼마나 느려졌는지, 특정 시뮬레이터에서만 실패하는지 등)는 집계되지 않습니다. 10번의 CI 실행 동안 안정적 상태에서 불안정 상태로 변하는 테스트는 단 한 번의 불운한 실행과 구별되지 않습니다.

테스트 인사이트는 모든 테스트의 결과와 소요 시간을 기록하고 실행 간 결과를 상관관계로 분석합니다. 느린 테스트, 실패, 불안정 테스트는 대시보드의 **Tests** 탭에 표시됩니다.

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**.
3. 앱 타겟에서 **Provide build settings from**을 선택하세요.
4. 붙여넣기: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. 테스트 작업을 한 번 실행하세요. 결과가 대시보드의 **Tests** 탭에 나타납니다.

## 번들 인사이트

IPA의 설치 및 다운로드 크기는 추가된 모든 자산과 링크된 모든 심볼에 따라 변동됩니다. Xcode는 **Product → Show Archive**에서 요청 시 크기를 보고하며, 시리즈 형태로 제공하지 않습니다. 대형 자산을 추가하는 PR은 병합 큐의 다른 PR과 구별되지 않습니다.

번들 인사이트는 분석된 모든 빌드의 설치 및 다운로드 크기를 기록하며, 브랜치별 임계값을 초과하면 PR 검사를 실패로 처리할 수 있습니다. 빌드 단계 직후 CI에 이를 추가하세요:

```bash
tuist inspect bundle App.ipa
```

대시보드에서 **Bundle insights**를 열어 추세를 확인하고 임계값을 구성하세요.

## 프리뷰

TestFlight는 공유할 때마다 빌드 및 검토 왕복 과정을 추가합니다. 서명된 `.ipa`를 직접 보내려면 프로비저닝 프로필에 수신자의 UDID가 필요합니다. 현재 브랜치를 간단히 시험해보려는 디자이너나 QA에게는 둘 다 편리하지 않습니다.

프리뷰는 빌드를 시뮬레이터 또는 기기에서 한 명령으로 실행할 수 있는 공유 가능한 링크로 변환합니다:

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

링크를 보내세요. 수신자는 `tuist run <url>` 또는 Tuist macOS 앱으로 이를 실행합니다.

## 팀을 참여시키기

캐시와 인사이트는 프로젝트에 연결된 인원 수에 따라 효과가 누적됩니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고, <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩이 개별적인 `tuist auth login` 대신 클릭 한 번으로 이루어지도록 하세요.

## 다음 단계

이 방식을 넘어설 경우, 가장 큰 단계는 Tuist가 생성하는 프로젝트입니다. 이는 실제 변화(`.xcodeproj` 대신 Swift 매니페스트로 타겟을 정의)이지만, 모듈 캐시와 선택적 테스팅을 가능하게 하는 핵심 요소입니다. <.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> 가이드에서 전체 과정을 다룹니다.
