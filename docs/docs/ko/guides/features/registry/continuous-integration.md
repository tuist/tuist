---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

CI에서 레지스트리를 사용하려면 워크플로우의 일부로 `tuist 레지스트리 로그인` 을 실행하여 레지스트리에 로그인했는지 확인해야 합니다.

::: info ONLY XCODE INTEGRATION
<!-- -->
사전 잠금 해제된 새 키체인을 생성하는 것은 Xcode 통합 패키지를 사용하는 경우에만 필요합니다.
<!-- -->
:::

레지스트리 자격 증명이 키 체인에 저장되므로 CI 환경에서 키 체인에 액세스할 수 있는지 확인해야 합니다.
Fastlane](https://fastlane.tools/)과 같은 일부 CI 공급자 또는 자동화 도구는 이미 임시 키체인을 만들거나 기본
제공 방법으로 키체인을 만드는 방법을 제공합니다. 그러나 다음 코드를 사용하여 사용자 지정 단계를 만들어 임시 키체인을 만들 수도 있습니다:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist 레지스트리 로그인` 은 기본 키체인에 자격 증명을 저장합니다. 기본 키체인을 생성하고 _잠금을 해제했는지 확인한 후_ `tuist
registry login` 을 실행합니다.

또한 `TUIST_TOKEN` 환경 변수가 설정되어 있는지 확인해야 합니다. 환경 변수는
<LocalizedLink href="/guides/server/authentication#as-a-project">here</LocalizedLink>
문서를 참조하여 만들 수 있습니다.

그러면 GitHub 액션의 워크플로 예시는 다음과 같습니다:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### 환경 전반에 걸친 점진적 해상도 향상 {#incremental-resolution-across-environments}

레지스트리를 사용하면 클린/콜드 해결이 약간 더 빨라지며, 해결된 종속성을 CI 빌드 전체에 유지하면 훨씬 더 큰 개선을 경험할 수 있습니다.
레지스트리 덕분에 저장 및 복원해야 하는 디렉터리의 크기가 레지스트리가 없을 때보다 훨씬 작아지므로 시간이 훨씬 적게 걸립니다. 기본 Xcode
패키지 통합을 사용할 때 종속성을 캐시하려면 `xcodebuild` 를 통해 종속성을 해결할 때 사용자 지정
`clonedSourcePackagesDirPath` 를 지정하는 것이 가장 좋은 방법입니다. 이는 `Config.swift` 파일에 다음을
추가하여 수행할 수 있습니다:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

또한 `Package.resolved` 의 경로를 찾아야 합니다. ` ls **/Package.resolved` 을 실행하여 경로를 가져올 수
있습니다. 경로는
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 과 같이
표시되어야 합니다.

Swift 패키지와 XcodeProj 기반 통합의 경우 프로젝트의 루트 또는 `Tuist` 디렉터리에 있는 기본 `.build` 디렉터리를
사용할 수 있습니다. 파이프라인을 설정할 때 경로가 올바른지 확인하세요.

다음은 기본 Xcode 패키지 통합을 사용할 때 종속성을 해결하고 캐싱하기 위한 GitHub 액션의 워크플로 예시입니다:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
