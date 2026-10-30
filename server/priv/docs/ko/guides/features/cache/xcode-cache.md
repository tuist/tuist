---
{
  "title": "Xcode 캐시",
  "titleTemplate": ":title · 캐시 · 기능 · 가이드 · Tuist",
  "description": "Tuist의 Xcode 캐시 통합으로 로컬 및 CI 환경에서 Xcode 빌드 속도를 높입니다."
}
---
# Xcode 캐시 {#xcode-cache}

Tuist는 Xcode 컴파일 캐시를 지원하며, 이를 통해 팀은 빌드 시스템의 캐싱 기능을 활용해 컴파일 아티팩트를 공유할 수 있습니다.

Xcode 캐시는 Xcode 26에서 도입되었습니다. Xcode 빌드 캐시라고도 불리며, 입력 값을 키로 사용해 컴파일 아티팩트를 재사용하고 Tuist의 원격 캐시를 통해 이러한 아티팩트를 여러 머신 간에 공유할 수 있게 합니다.

> [!TIP]
> **모듈 캐시와 함께 사용**
>
> Xcode 캐시와 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link>는 서로 다른 세분화 수준에서 작동하며 상호 보완적입니다. 모듈 캐시는 빌드 실행 전에 전체 모듈을 미리 빌드된 `.xcframework`로 교체하는 반면, Xcode 캐시는 빌드 중에 컴파일 출력을 재사용합니다.

> [!TIP]
> **개발자 머신에서 정리 시 `CompilationCache.noindex` 유지**
>
> 기본적으로 컴파일 캐시 저장소는 `DerivedData` 내부에 위치하므로, `DerivedData`를 삭제하면 빌드 결과물과 함께 캐시도 제거됩니다. 개발자 머신에서는 빌드 결과물만 삭제하는 것을 선호하세요. 이렇게 하면 다시 빌드할 때 네트워크에서 아무것도 가져오지 않고 디스크의 저장소에서 재생합니다.

## 설정 {#setup}

Tuist 계정과 프로젝트가 아직 없다면 다음 명령어를 실행하여 생성할 수 있습니다:

```bash
tuist init
```

`Tuist.swift` 파일에 `fullHandle`를 참조하도록 설정한 후, 다음 명령어를 실행하여 프로젝트의 캐싱을 설정할 수 있습니다:

```bash
tuist setup cache
```

이 명령어는 Swift [빌드 시스템](https://github.com/swiftlang/swift-build)이 컴파일 아티팩트를 공유하기 위해 사용하는 로컬 캐시 서비스를 시작 시 실행하는 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)를 생성합니다. 처음에는 개발자 머신에서 실행하고, 각 CI 작업의 설정 과정에도 포함하세요.

CI에서 캐시를 설정하려면 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증</.localized_link>되었는지 확인하세요.

### 캐시 구성 요소 업데이트 {#updating-the-cache-components}

캐시 프록시는 마지막으로 설정을 실행한 Tuist 설치 경로에 고정되지 않고 안정적인 런처를 사용합니다. 일단 설치되면 `tuist setup cache` 및 캐시가 활성화된 `tuist generate`는 사용 가능한 타겟을 최신 Tuist 릴리스로 업그레이드합니다. 따라서 구버전 Tuist에 고정된 프로젝트라도 공유 프록시를 다운그레이드하지 않습니다. 생성(Generation)은 기존 런처 타겟만 업데이트하며, 서비스 설치, 인증, 플러그인 교체 또는 프록시 재시작은 수행하지 않습니다. 사용자 정의 플러그인, 프록시, 소켓 또는 레지스트리 재정의가 있는 경우 자동 업그레이드는 건너뜁니다.

실행 중인 프록시는 캐시 요청이 최소 30초 동안 없고, 진행 중인 요청이나 백그라운드 작업이 없으며 발행 스풀이 모두 비워진 후에만 새 타겟을 적용합니다. 그 후 종료되고 launchd가 선택된 CLI를 시작하며 서비스의 인수와 자격 증명 환경을 유지합니다. 실제로 타겟을 적용한 프록시만 번들에서 디스크 상의 플러그인을 원자적으로 새로 고칩니다. 이전 프록시가 여전히 드레이닝 중일 때는 설정이 새 플러그인을 설치하지 않습니다. 설치된 플러그인이 누락된 경우 명시적인 유휴 상태 설정이 선택된 프록시를 재시작하여 새로 고침을 재시도합니다. 레지스트리와 스풀을 소유하는 프록시는 여전히 하나뿐입니다. 사용할 수 없는 타겟이나 드레이닝되지 않은 업로드는 활성 요청을 중단하지 않고 전환을 지연시킵니다. 자격 증명 새로 고침은 전환 전에도 선택된 CLI를 따르므로, 구버전 CLI 설치를 제거해도 드레이닝을 기다리는 업로드가 고립되지 않습니다.

안정적인 런처 이전에 생성된 기존 설치본은 한 번의 명시적 마이그레이션이 필요합니다. 빌드가 실행 중이지 않을 때 다음을 실행하세요:

```bash
tuist setup cache
```

마이그레이션 후에는 Tuist를 업데이트하고 평소대로 `tuist generate`를 실행하는 것만으로 프록시와 설치된 플러그인을 업그레이드할 수 있으며, 각 CLI 릴리스마다 설정을 다시 실행할 필요가 없습니다. 동일한 경로의 Xcode를 포함한 다른 Xcode를 선택하려면 여전히 명시적 설정이 필요합니다. 구성이 변경될 때 설정이 공유 서비스를 대체할 수 있으므로, 먼저 머신의 모든 빌드가 완료될 때까지 기다리세요. 프록시는 이전 플러그인 프로토콜과 현재 프로토콜을 모두 지원하므로, Xcode에 이미 로드된 호환 플러그인은 프록시 업그레이드 중에도 계속 작동합니다. 최신 플러그인을 로드하려면 Xcode를 완전히 종료하고 다시 열어야 하지만, 호환되는 플러그인이 이미 로드되어 있다면 즉시 재시작할 필요는 없습니다. 릴리스에서 생성된 빌드 설정이 변경되면 프로젝트를 다시 생성하세요.

선택된 Tuist 설치본을 사용 가능 상태로 유지하세요. 런처는 시작, 구성 및 자격 증명 새로 고침에 이를 사용합니다. 런처가 업그레이드되면 구버전 설치본은 제거할 수 있습니다. 선택된 실행 파일이 삭제되었거나 더 이상 실행 가능하지 않은 경우, `tuist setup cache`는 캐시를 먼저 해제하지 않고도 사용 가능한 설치본(구버전 릴리스 포함)을 사용하여 타겟을 복구할 수 있습니다. 안정적인 실행 파일 별칭은 패키지 관리자 업그레이드Across에서도 유지되며, 심볼릭 링크는 설치 ID를 비교할 때만 해결됩니다. 시작 시 프록시는 실제 실행된 버전(인플레이스 업데이트나 의도적인 롤백 포함)을 기록하며, 관련 없는 구버전 체크아웃이 사용 가능한 설치본으로 전환하는 것을 방지하기 위해 사용된 최고 버전을 유지합니다.

릴리스 버전이 없는 소스 빌드 CLI와 명시적 `TUIST_CAS_PLUGIN_PATH` 또는 `TUIST_CAS_PROXY_PATH` 설정은 자동 버전 선택 대신 명시적 실행 구성을 사용합니다. 해당 구성 요소를 다시 빌드한 후 설정을 다시 실행하세요. 설정은 신선도를 확인하고 대체 준비가 완료된 후에만 관리되는 타겟 업그레이드를 비활성화합니다.

`tuist teardown cache`는 런처 타겟을 제거하기 전에 서비스를 중지하며, 기존 프로젝트를 위한 안정적인 플러그인은 유지합니다. 서비스 중지에 실패하면 런처는 재시작 및 또 다른 해체 시도를 위해 사용 가능한 상태로 남습니다. 성공적인 해체 후에는 생성으로 서비스를 다시 만들 수 없습니다.

### Xcode 빌드 설정 구성 {#configure-xcode-build-settings}

기존 Xcode 프로젝트의 경우, `tuist setup cache`에서 출력된 빌드 설정을 프로젝트의 Build Settings 또는 기존 `.xcconfig` 파일에 복사하세요. 이 명령어는 계정에 대한 구성을 출력하며, 구성 파일을 생성하거나 Xcode 프로젝트를 편집하지는 않습니다. `OTHER_SWIFT_FLAGS`를 확장할 때 `$(inherited)`를 유지하여 다른 컴파일러 옵션이 보존되도록 하세요.

설정에는 다음이 포함됩니다:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

`COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 및 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`는 Xcode의 빌드 설정 UI에 직접 노출되지 않으므로 **사용자 정의 빌드 설정**으로 추가해야 합니다.

> [!NOTE]
> **플러그인 경로**
>
> `libtuist_cas_plugin.dylib`는 Tuist와 함께 제공되는 컴파일 캐시 플러그인으로, `tuist` 실행 파일 옆에 위치합니다. `tuist setup cache`는 이를 `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`에 복사하며, `COMPILATION_CACHE_PLUGIN_PATH`는 해당 복사본을 가리킵니다. 이 경로는 모든 머신에서 동일하며 Tuist를 업데이트해도 변경되지 않으므로 프로젝트와 함께 설정을 커밋할 수 있습니다. 설정과 새로 시작된 프록시는 선택된 Tuist 번들에서 복사본을 새로 고칩니다. 이전 체크아웃에서 설정을 실행해도 최신 플러그인이 다운그레이드되지 않습니다.

> [!NOTE]
> **모든 프로젝트를 위한 단일 소켓**
>
> `tuist setup cache`는 머신당 하나의 캐시 프록시를 설치하므로 모든 프로젝트가 동일한 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`를 사용합니다. `tuist-instance` 플러그인 옵션이 프로젝트를 식별합니다.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`가 C와 Objective-C를 공유하는 방식**
>
> 이 설정을 "캐시 서비스가 위치한 곳"으로 읽고 선택 사항으로 취급하기 쉽습니다. 하지만 이는 C, Objective-C, 사전 컴파일된 모듈 및 사전 컴파일된 헤더를 공유할지 여부를 결정하는 스위치이기도 합니다. 빌드 시스템은 원격 캐시 서비스가 구성된 경우에만 이러한 항목에 대한 캐싱을 실행합니다. 이를 생략하면 Swift 컴파일은 여전히 공유되지만, 이전에 프로젝트를 빌드하지 않은 머신에서는 모든 C/Objective-C 파일과 모든 모듈이 다시 컴파일됩니다.

> [!NOTE]
> **동시 캐시 조회**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`는 빌드의 실행 레인에서 한 번에 몇 개씩 처리하는 대신, 나머지 빌드와 함께 각 컴파일에 대해 빌드 시스템이 수행하는 원격 캐시 조회를 실행합니다. 원격 캐시에서 많은 컴파일을 누락하거나 복원하는 빌드는 더 빨리 완료됩니다.

다음과 같은 플래그를 추가하여 `xcodebuild`를 실행할 때 이러한 설정을 지정할 수도 있습니다.

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Xcode 27 이상에서의 접두사 매핑**
>
> Xcode 27 이상에서는 `tuist setup cache`가 `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` 및 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`도 출력합니다. 이들은 프로젝트와 `DerivedData`의 위치에 독립적인 컴파일 캐시 키를 만듭니다. 사용자 정의 빌드 설정으로 추가하세요. 이를 활성화하면 모든 캐시 키가 변경되므로 다음 빌드에서 캐시가 다시 채워집니다. `enableCaching`가 켜져 있으면 `tuist generate`가 이를 자동으로 설정해 줍니다.
>
> 컴파일러는 매핑된 경로를 코드 커버리지 데이터에도 기록하며, Xcode는 이를 해결할 수 없으므로 커버리지 보고서에는 접두사 매핑으로 컴파일된 모든 소스가 제외됩니다. 출력된 설정과 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 설정은 코드 커버리지를 수집하는 빌드에서 접두사 매핑을 비활성화합니다. `tuist generate`도 마찬가지입니다. 이러한 빌드는 여전히 컴파일 캐시를 사용하지만, 캐시 키는 프로젝트와 `DerivedData` 경로에 의존합니다.
>
> 명령줄에서 `xcodebuild`에 이러한 설정을 전달할 때는 위의 `OTHER_SWIFT_FLAGS`와 마찬가지로 `$(...)`를 포함하는 값을 작은따옴표로 묶으세요. 그렇지 않으면 셸이 이를 빈 문자열로 확장하여 접두사 매핑이 비활성화됩니다.
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **생성된 프로젝트**
>
> 프로젝트가 Tuist에 의해 생성되는 경우 설정을 수동으로 구성할 필요가 없습니다.
>
> 이 경우 `Tuist.swift` 파일에 `enableCaching: true`만 추가하면 됩니다.
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### 접두사 매핑을 사용한 커버리지 {#coverage-with-prefix-mapping}

기본적으로 생성된 프로젝트는 Xcode의 커버리지 보고서와 `xccov`가 작동하도록 유지하기 위해 커버리지 빌드에 대한 접두사 매핑을 비활성화합니다. 체크아웃 간에 커버리지 컴파일을 공유 가능하게 유지하려면 이를 활성화할 수 있습니다.

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

`TUIST_COVERAGE_PREFIX_MAPPING` 환경 변수(`1` 또는 `0`)는 `prefixMapping`보다 우선합니다. 이 옵션은 Xcode 27 이상에 적용되며 `enableCaching`가 필요합니다. 커버리지 `tuist test` 업로드는 이를 지원합니다. Tuist는 `llvm-cov`를 사용하여 실행을 측정하며, 이는 매핑된 경로로 소스를 읽고 리포지토리의 파일과 연결합니다. Xcode 자체의 커버리지 보고서와 `xccov`는 여전히 해당 소스를 생략할 수 있으며, `llvm-cov` 내보내기가 실패하여 결과 번들의 `xccov` 보고서로 대체되는 업로드도 마찬가지입니다. 매핑된 `#filePath` 값은 소스 파일을 기준으로 픽스처를 찾는 테스트에도 영향을 줄 수 있습니다. 대신 명시적 런타임 체크아웃 경로를 통해 픽스처를 해결하세요. 커버리지를 직접 처리하는 경우, 각 계측된 바이너리를 해당 타겟의 `$(TARGET_TEMP_DIR)/compilation-prefix-map.json`와 쌍으로 맞추세요. 이는 가상 접두사를 로컬 디렉터리로 다시 매핑합니다. 프로젝트별 매핑이 활성화된 경우 모든 바이너리에 대해 한 타겟의 맵을 재사용하지 마세요.

커버리지 접두사 설정은 커버리지 아티팩트에 기록된 경로를 제어하므로 바이너리 캐시 및 선택적 테스트 해시에 참여합니다. 이 옵션을 변경하거나 `TUIST_COVERAGE_PREFIX_MAPPING`를 다르게 설정하면 일반 빌드에서도 해당 해시가 무효화됩니다. 개발자와 CI 작업 간에 바이너리 캐시 및 선택적 테스트 결과를 공유해야 하는 경우 값을 일관되게 유지하세요.

### 생성된 프로젝트 디버깅 {#debugging-generated-projects}

복원된 네이티브 모듈은 링크된 디버그 정보뿐만 아니라 컴파일 캐시에 대한 액세스도 필요합니다. Tuist는 dSYM과 슬라이스별 소스 식별 메타데이터로 Debug 및 Release 모듈을 워밍업한 후, 타겟을 교체하기 전에 소비자가 선언한 소스와 메타데이터를 검증합니다. 메타데이터가 누락되거나 호환되지 않으면 해당 타겟의 소스가 유지됩니다. 스크립트로 생성된 `.generated(...)` 소스는 검증 가능한 콘텐츠 체크섬 대신 선언 지문을 가지므로, 이러한 타겟은 소스 빌드로 유지되며 네이티브 모듈 캐시에 게시되지 않습니다. 실제 콘텐츠 체크섬이 있는 생성된 리소스 접근자는 여전히 대상이 됩니다. 지원되지 않는 디버그 정보는 관련 없는 제품의 차단을 방지하면서 영향받은 타겟의 게시를 건너뜁니다. 소스 변형 및 취소는 여전히 워밍업을 실패시킵니다. 캐시 형식이 변경되므로 이전 버전으로 워밍업된 아티팩트는 재워밍업이 필요합니다.

검증된 교체를 위해 Tuist는 소비자 소유의 dSYM UUID plist에서 소스 재배치를 준비하고 정적 캐시 코드를 위한 디버그 전용 동반자를 링크합니다. 이는 캐시된 바이너리를 다시 작성하거나 LLDB의 영구 전역 소스 맵에 프로듀서 소스 경로를 설치하지 않습니다. 명시적 디버거 초기화 프로그램과 모듈 로더 설정이 여전히 권위적입니다. 디버그 심볼과 소스 재배치는 소스 상대 런타임 파일 액세스나 네이티브 Xcode 커버리지 보고서를 복구하지 않습니다. 커버리지 변형 선택과 LLVM 내보내기는 별도의 기능으로 남습니다.

`enableCaching: true`를 사용하면 Tuist는 Run 및 Test 액션에 대해 LLDB 소스 맵을 구성합니다. 액션에 사용자 지정 LLDB 초기화 프로그램이 있는 경우, Tuist는 먼저 해결된 소스 맵을 작성한 다음 사용자 지정 초기화 프로그램을 소싱하여 맵을 확장하거나 재정의할 수 있도록 합니다. 그렇지 않으면 소스 맵을 교체하기 전에 파일이 존재하면 `~/.lldbinit-Xcode`를 로드하고, 없으면 `~/.lldbinit`로 대체합니다. 하나의 홈 파일만 로드하여 이중 소싱 없이 사용자별 디버거 설정을 복원합니다. 교체는 이전 실행의 오래된 매핑을 제거하며 홈 파일 소스 맵보다 우선합니다. 유지되어야 하는 소스 맵 항목은 액션의 사용자 지정 초기화 프로그램에 배치하세요. 다른 홈 설정은 보존됩니다. Tuist의 캐시별 모듈 검색 경로, 로더 설정 및 Clang 플래그는 이후에 적용되며 해당 설정의 사용자 값보다 우선합니다. 홈 파일 오류는 이후 명령의 로드를 중단하지 않고 표시되며, 명령은 에코되지 않습니다. 이 초기화 프로그램 보존은 모듈 캐시에서 복원된 바이너리에 대한 디버깅을 Tuist가 구성할 때도 적용되며, `enableCaching`가 없거나 이전 Xcode 버전에서도 마찬가지입니다.

Xcode 27 이상에서는 프로젝트에서 명시적으로 설정하지 않는 한, 생성된 프로젝트가 Xcode의 프로젝트별 접두사 매핑(`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 및 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`)을 비활성화된 상태로 둡니다. `/^src`와 같은 접두사는 각 프로젝트마다 다른 디렉터리를 지칭하며, LLDB는 디버그 대상 타겟의 프로젝트에 대해서만 이를 해결합니다. 대신 소스는 워크스페이스 전체 접두사 아래에 기록됩니다: Tuist 루트 디렉터리용 `/^root`, Swift 패키지 스크래치 디렉터리용 `/^spm`, 그리고 빌드 출력물용 `/^intermediates` 및 `/^products`. 각각은 모든 프로젝트에서 동일한 디렉터리를 지칭하므로, 워크스페이스 내 모든 프로젝트의 소스에서 중단점이 해결됩니다.

Tuist 루트 외부의 경로는 매핑되지 않습니다. 루트 외부 프로젝트의 캐시 키는 체크아웃 위치에 따라 달라지므로, 다른 체크아웃 및 머신에서는 해당 캐시를_miss_합니다. 키가 체크아웃 위치와 독립적이도록 하려면 해당 프로젝트의 manifest에서 프로젝트별 매핑을 활성화하세요:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

이 설정을 해당 `Project`에 전달하세요. 다른 프로젝트의 타겟을 디버깅할 때 LLDB는 해당 프로젝트의 소스를 찾을 수 없습니다. Manifest 프로젝트 기본 설정은 프로젝트 수준 xcconfig 값보다 우선하므로, manifest 자체에서 설정하세요.

이러한 설정을 변경하면 컴파일 캐시 키, 바이너리 캐시 해시 및 선택적 테스트 해시가 변경되므로 해당 캐시를 다시 워밍업해야 합니다. 팀 전체에서 이 선택을 일관되게 유지하세요.

### 캐시 업로드 정책 {#cache-upload-policy}

기본적으로 캐시 서비스는 원격 캐시에 아티팩트를 다운로드하고 업로드합니다. `Tuist.swift` 파일의 `xcodeCache` 옵션을 사용하여 읽기 전용 모드를 활성화하여 이를 제어할 수 있습니다. 이 모드에서는 아티팩트가 다운로드되지만 업로드되지는 않습니다:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

일반적인 패턴은 로컬 환경을 읽기 전용으로 유지하면서, 빌드가 재현 가능한 CI에서만 아티팩트를 푸시하는 것입니다. 대부분의 CI 제공자가 설정하는 `CI` 환경 변수를 확인하는 `Environment.isCI`를 사용하여 이를 달성할 수 있습니다:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

이 설정을 사용하면 로컬 빌드는 업로드 없이 캐시된 아티팩트의 이점을 얻으며, CI 빌드는 팀의 나머지 구성원을 위해 캐시를 채웁니다.

업로드 정책은 `tuist setup cache`를 실행하는 머신에서 프로젝트별로 기록됩니다. 이를 변경하려면 `upload`를 업데이트하고 `tuist setup cache`를 다시 실행하세요. Tuist가 프로젝트를 생성하는 경우 `tuist generate`도 실행하세요. 그 이후의 업로드는 해당 머신의 캐시를 재시작하지 않고 새 정책을 따릅니다. 동일한 머신에서 동시에 실행되는 동일 프로젝트의 작업은 정책을 공유하므로, 가장 최근의 `tuist setup cache`가 모든 작업의 정책을 결정합니다.

### 스토어 크기 제한 {#store-size-limit}

컴파일 캐시 스토어는 빌드마다 증가합니다. 프로젝트의 스토어 크기를 제한하려면 `Tuist.swift` 파일에서 `storeSizeLimit`를 설정하세요:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

빌드가 실행 중이지 않을 때 Tuist는 10분마다 프로젝트의 각 스토어를 확인합니다. 새로운 빌드가 제한의 약 절반을 기록하면 스토어의 가장 오래된 캐시 출력을 삭제하므로, 스토어는 대략 제한 크기에서 안정화됩니다. 빌드가 실행 중일 때는 스토어가 제한보다 클 수 있으며, 제한을 설정했을 때 이미 더 컸던 스토어는 새로운 빌드가 그만큼 기록되면 축소됩니다. 여러 프로젝트가 기본 위치처럼 동일한 스토어를 사용하는 경우, 가장 작은 제한이 적용됩니다. 제한은 `tuist setup cache`를 실행하는 모든 머신에 적용되므로, 제한을 변경한 후 다시 실행하세요.

### 모듈 캐시 해시 {#module-cache-hashes}

컴파일 캐시 설정은 <.localized_link href="/guides/features/projects/hashing">모듈 캐시 해시</.localized_link>의 일부가 아닙니다. Tuist는 모든 `COMPILATION_CACHE_*` 빌드 설정과 값이 포함된 모든 `-cas-plugin-option` 플래그를 해시에서 제외합니다. `enableCaching`를 켜거나 끄거나 업로드 정책을 변경해도 타겟의 해시는 유지되므로, 이미 워밍업된 <.localized_link href="/guides/features/cache/module-cache">모듈 캐시</.localized_link> 바이너리는 유효하게 남습니다. Xcode 캐시가 있는 빌드와 없는 빌드를 동일한 모듈 캐시와 비교할 수 있습니다.

> [!NOTE]
> **접두사 매핑 설정은 해시됩니다**
>
> Xcode 27 이상에서는 `enableCaching: true`가 `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 및 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 설정도 설정합니다. 이러한 설정은 모듈 캐시 해시의 일부이므로, Xcode 27 이상에서는 `enableCaching`를 켜거나 끄면 타겟의 해시가 변경됩니다.

### 대형 출력물의 일부 재사용 {#reusing-parts-of-large-outputs}

Xcode 캐시는 콘텐츠 정의 청킹을 통해 전송량을 줄일 수 있습니다. 각 대형 출력물을 이전 버전과 무관하게 취급하는 대신, 콘텐츠에 의해 결정된 경계에서 압축된 출력물을 분할합니다. 편집 후 오프셋이 변경되더라도 일치하는 청크는 재사용될 수 있습니다.

업로드는 서버에 누락된 청크만 전송합니다. 다운로드는 먼저 정확한 캐시된 액션과 출력물의 청크 레시피를 가져온 다음, 로컬 머신에 저장된 검증된 청크를 재사용하고 누락된 부분을 가져옵니다. 완전하게 재구성된 출력물은 컴파일러 캐시에 복원되기 전에 검증됩니다.

전송 청크 캐시는 `DerivedData`와 분리되어 있으므로, 컴파일 캐시를 정리하거나 로컬 캐시 서비스를 재시작해도 청크가 유지될 수 있습니다. 이는 일회성이며 최대 1GiB의 청크 페이로드와 최대 2MiB의 추가 임시 스테이징 파일로 제한됩니다. 제거되거나 손상된 청크는 필요할 때 다시 다운로드됩니다. 컴파일 캐시 자체를 유지하는 것이 콘텐츠를 재구성하는 것보다 여전히 빠릅니다.

클라이언트는 서버가 호환되는 지원을 광고할 때만 청크 전송을 사용합니다. 이전 클라이언트는 여전히 전체 출력을 읽을 수 있으며, 이전 버전이거나 지원되지 않는 서버에 연결된 클라이언트는 일반 전송을 유지합니다. 작은 출력물은 기존 전체 출력 경로를 그대로 사용합니다.

이는 전송 바이트를 줄이지만 컴파일러 무효화를 줄이지는 않습니다. 소스 파일을 변경하면 여전히 컴파일이 필요할 수 있습니다. 청킹은 결과 출력물을 게시하거나 복원하는 데 도움이 됩니다. 절감 효과는 출력물과 편집 내용에 따라 다르며, 일치하는 청크가 없는 콜드 머신은 모든 출력물을 다운로드해야 합니다.

### 지속적 통합 {#continuous-integration}

CI 환경에서 캐싱을 활성화하려면 로컬 환경과 동일한 명령어를 실행해야 합니다: `tuist setup cache`.

인증에는 지원되는 CI 제공업체에 권장되는 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link> 또는 `TUIST_TOKEN` 환경 변수를 통한 <.localized_link href="/guides/server/authentication#account-tokens">계정 토큰</.localized_link>을 사용할 수 있습니다.

OIDC 인증을 사용하는 GitHub Actions 워크플로우 예시:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

토큰 기반 인증 및 Xcode Cloud, CircleCI, Bitrise, Codemagic과 같은 다른 CI 플랫폼을 포함한 더 많은 예시는 <.localized_link href="/guides/integrations/continuous-integration">지속적 통합 가이드</.localized_link>를 참조하세요.

### CI의 컴파일 캐시 스토어 {#compilation-cache-store-on-ci}

컴파일 캐시 스토어는 Xcode가 컴파일 출력물을 보관하는 로컬 디렉터리입니다. `COMPILATION_CACHE_CAS_PATH` 빌드 설정이 해당 위치를 지정하며, 기본값은 `DerivedData` 내부의 `CompilationCache.noindex`입니다.

#### 상태 저장 스토어 {#stateful-store}

빌드 간에 스토어를 유지하려면 `COMPILATION_CACHE_CAS_PATH`(및 `tuist cache`용 `TUIST_COMPILATION_CACHE_CAS_PATH`)를 하나의 영구 경로로 지정하고 [스토어 크기 제한](#store-size-limit)으로 크기를 제한하세요.

## 문제 해결 {#troubleshooting}

### 빌드가 Xcode 캐시 프록시 실패를 경고함 {#cas-proxy-failed}

빌드가 다음과 같은 경고를 표시하는 경우(Xcode는 먼저 실패한 컴파일에 따라 `CAS error:` 또는 `CAS operation failed:` 접두사를 붙임):

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

컴파일 캐시가 `tuist setup cache`가 설치한 로컬 캐시 프록시에 도달하지 못한 것입니다. 빌드는 여전히 성공하지만, 영향을 받은 컴파일은 원격 캐시 히트를 얻지 못하므로 빈 캐시로 빌드하는 것과 같이 실행됩니다. 업로드 내용은 디스크에 보관되며 프록시가 다시 요청을 처리할 때 전송됩니다. 제시간에 복구되면 동일 빌드 내 나중에, 그렇지 않으면 동일 머신의 다음 빌드 중에 전송됩니다. 작업 후 폐기되는 CI 머신에서는 이러한 데이터가 손실됩니다. 경고는 빌드당 한 번씩 Xcode의 Issue navigator와 `xcodebuild` 출력에 나타납니다.

프록시가 실행 중인지 확인하려면 경고에 명시된 소켓을 수신 중인 프로세스를 찾으세요:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

명령어가 아무것도 출력하지 않으면 `tuist setup cache`를 실행하여 프록시를 다시 시작하세요. CI에서는 모든 작업에서 `xcodebuild` 호출 전에 `tuist setup cache`를 실행하세요.

### 빌드가 극도로 느리고 `CAS error: deadlineExceeded` 경고를 발생시킴 {#cas-deadline-exceeded}

빌드가 예상보다 훨씬 오래 걸리고 Xcode 빌드 로그에 다음과 같은 경고가 가득한 경우:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

또는:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH`가 아무도 수신하지 않는 소켓(일반적으로 이전 버전의 Tuist가 구성한 프로젝트별 소켓(`~/.local/state/tuist/<org>_<project>.sock`))을 가리키고 있습니다. Tuist는 더 이상 해당 소켓을 제공하지 않습니다. Xcode는 빠르게 실패하는 대신 모든 컴파일 캐시 요청마다 연결을 재시도하므로 빌드가 한 시간 이상 걸릴 수 있으며, Tuist는 이 동작을 변경할 수 없습니다.

해결 방법:

- **생성된 프로젝트**: `tuist generate`를 다시 실행하세요.
- **다른 프로젝트**: [Xcode 빌드 설정 구성](#configure-xcode-build-settings)에 설명된 대로 `COMPILATION_CACHE_*` 빌드 설정을 `tuist setup cache`가 출력하는 설정으로 교체하세요.

Xcode 캐시를 사용하지 않는 경우 대신 `COMPILATION_CACHE_*` 빌드 설정을 제거하고 `tuist teardown cache`를 실행하세요.

### 업로드가 비활성화되어いても 로컬에서 `uploaded CAS output`가 나타남 {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)`(또는 비-CI 머신에서 `upload: Environment.isCI`)가 설정된 경우 빌드 로그에서 여전히 `note: uploaded CAS output ...`를 볼 수 있습니다. `xcodebuild`는 이러한 호출을 건너뛸 방법이 없으므로 Tuist는 이를 수신하지만 Tuist 서버에 아무것도 게시하지 않습니다. 대시보드 지표는 이를 반영하므로 잘못된 업로드 트래픽이 보고되지 않습니다.
