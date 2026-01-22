---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 지속 통합 {#continuous-integration}

CI에서 레지스트리를 사용하려면 워크플로 일환으로 `tuist registry login` 를 실행하여 레지스트리에 로그인했는지 확인해야
합니다.

::: info ONLY XCODE INTEGRATION
<!-- -->
패키지의 Xcode 통합을 사용하는 경우에만 사전 잠금 해제된 키체인 생성が必要です.
<!-- -->
:::

레지스트리 자격 증명이 키체인에 저장되므로 CI 환경에서 키체인에 접근할 수 있는지 확인해야 합니다. 일부 CI 제공업체나
[Fastlane](https://fastlane.tools/)과 같은 자동화 도구는 이미 임시 키체인을 생성하거나 키체인 생성 방법을 내장하고
있습니다. 그러나 다음 코드로 커스텀 단계를 생성하여 직접 키체인을 만들 수도 있습니다:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`_ `tuist 레지스트리 로그인` 은 이후 기본 키체인에 자격 증명을 저장합니다. tuist 레지스트리 로그인` 을 실행하기 전에 기본
키체인이 생성되고 잠금 해제되었는지 확인하십시오. _

추가로, 환경 변수 ` `` 또는 `TUIST_TOKEN`(` )이 설정되어 있는지 확인해야 합니다.
<LocalizedLink href="/guides/server/authentication#as-a-project">여기</LocalizedLink>의
문서를 따라 생성할 수 있습니다.

GitHub Action의 Workflow 예시는 다음과 같을 수 있습니다:
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

레지스트리를 사용하면 클린/콜드 해결 속도가 약간 빨라지며, CI 빌드 간에 해결된 종속성을 유지하면 더 큰 개선 효과를 경험할 수 있습니다.
레지스트리 덕분에 저장 및 복원해야 하는 디렉터리 크기가 레지스트리 미사용 시보다 훨씬 작아져 시간이 크게 단축됩니다. 기본 Xcode 패키지
통합을 사용할 때 종속성을 캐시하는 가장 좋은 방법은 `xcodebuild` 를 통해 종속성을 해결할 때 커스텀
`clonedSourcePackagesDirPath` 를 지정하는 것입니다. 이는 `Config.swift` 파일에 다음을 추가하여 수행할 수
있습니다:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

추가로, `Package.resolved` 의 경로를 찾아야 합니다. `ls **/Package.resolved` 를 실행하여 경로를 확인할 수
있습니다. 경로는 대략 다음과 같아야 합니다:
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Swift 패키지 및 XcodeProj 기반 통합의 경우, 프로젝트 루트 또는 `Tuist` 디렉토리 내에 위치한 기본 `.build`
디렉토리를 사용할 수 있습니다. 파이프라인 설정 시 경로가 정확한지 확인하십시오.

기본 Xcode 패키지 통합을 사용할 때 종속성을 해결하고 캐싱하기 위한 GitHub Actions의 예시 워크플로는 다음과 같습니다:
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
