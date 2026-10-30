---
{
  "title": "지속적 통합",
  "titleTemplate": ":title · Swift · 패키지 레지스트리 · 기능 · 가이드 · Tuist",
  "description": "지속적 통합 환경에서 Tuist Registry를 사용하는 방법을 알아보세요."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

레지스트리는 추가 인증 설정 없이 CI에서 바로 작동합니다. 기본적으로 인증되지 않은 요청은 IP 주소당 **분당 1,000회 요청**으로 속도 제한됩니다.

**분당 20,000회 요청**의 더 높은 속도 제한이 필요하다면 `tuist registry login`를 실행하여 인증할 수 있습니다. 이때 `TUIST_TOKEN` 환경 변수가 설정되어 있어야 합니다. 프로젝트 토큰은 <.localized_link href="/guides/server/authentication#as-a-project">여기</.localized_link>의 문서를 따라 생성할 수 있습니다.

> [!NOTE]
> 아래의 키체인 설정은 `tuist registry login`를 사용하여 더 높은 속도 제한을 얻으려는 경우에만 필요합니다. 대부분의 경우 기본 인증 없는 속도 제한으로 충분하므로 이 단계를 완전히 건너뛸 수 있습니다.
>
> 또한 새 사전 잠금 해제 키체인을 생성하는 것은 패키지의 Xcode 통합을 사용할 때만 필요합니다.


`tuist registry login`는 자격 증명을 키체인에 저장하므로 CI 환경에서 키체인에 접근할 수 있는지 확인해야 합니다. 일부 CI 제공업체나 [Fastlane](https://fastlane.tools/)과 같은 자동화 도구는 이미 임시 키체인을 생성하거나 생성 방법을 내장되어 제공합니다. 하지만 다음 코드로カスタム 스텝을 만들어 직접 생성할 수도 있습니다.
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

기본 키체인이 생성되고 잠금이 해제되었는지 _이전에_ `tuist registry login`를 실행하세요.

### 환경 간 증분 해결 {#incremental-resolution-across-environments}

우리 레지스트리를 사용하면 초기/콜드 해결 속도가 약간 더 빨라지며, CI 빌드 전반에 걸쳐 해결된 의존성을 지속하면 더 큰 개선 효과를 경험할 수 있습니다. 레지스트리 덕분에 저장하고 복원해야 하는 디렉터리 크기가 레지스트리 없이 사용할 때보다 훨씬 작아져 시간이 크게 단축됩니다. 기본 Xcode 패키지 통합을 사용할 때 의존성을 캐시하려면 `xcodebuild`를 통해 의존성을 해결할 때カスタム `clonedSourcePackagesDirPath`를 지정하는 것이 가장 좋습니다. 이는 `Config.swift` 파일에 다음을 추가하여 수행할 수 있습니다.

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

또한 `Package.resolved`의 경로를 찾아야 합니다. `ls **/Package.resolved`를 실행하여 경로를 확인할 수 있습니다. 경로는 `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`와 비슷해야 합니다.

Swift 패키지 및 XcodeProj 기반 통합의 경우 프로젝트 루트 또는 `Tuist` 디렉터리에 있는 기본 `.build` 디렉터리를 사용할 수 있습니다. 파이프라인을 설정할 때 경로가 올바른지 확인하세요.

다음은 기본 Xcode 패키지 통합을 사용할 때 의존성을 해결하고 캐시하기 위한 GitHub Actions 워크플로 예시입니다:
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
