---
{
  "title": "모듈 캐시",
  "titleTemplate": ":title · 캐시 · 기능 · 가이드 · Tuist",
  "description": "컴파일된 바이너리를 캐시하고 Tuist 모듈 캐시로 팀 전체에 공유하세요."
}
---

# 모듈 캐시 {#module-cache}

> [!WARNING]
> **필수 조건**
>
> - <.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>. 모듈 캐시는 `Project.swift` 뒤에 Tuist가 유지하는 프로젝트 그래프를 읽어 타겟을 해시하고 해당 바이너리로 대체합니다.

Tuist 모듈 캐시는 모듈을 바이너리(`.xcframework`s)로 캐시하고 다양한 환경에서 공유함으로써 빌드 시간을 최적화하는 강력한 방법을 제공합니다. 이 기능을 통해 이전에 생성된 바이너리를 활용하여 반복적인 컴파일을 줄이고 개발 프로세스를 가속화할 수 있습니다.

> [!TIP]
> **Xcode 캐시와 함께 사용**
>
> 모듈 캐시와 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 캐시</.localized_link>는 서로 다른 세분화 수준에서 작동하므로 상호 보완적입니다. 모듈 캐시는 빌드 실행 전에 전체 모듈을 사전 빌드된 `.xcframework`s로 교체하는 반면, Xcode 캐시는 빌드 중에 컴파일 출력을 재사용합니다.
>
> 컴파일 캐시 설정은 모듈 캐시 해시의 일부가 아니므로 Xcode 캐시를 켜거나 꺼도 이미 워밍업된 바이너리가 유지됩니다. Xcode 27 이상에서는 이와 함께 제공되는 접두사 매핑 설정이 해시됩니다. <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">모듈 캐시 해시</.localized_link>를 참조하세요.

## 워밍업 {#warming}

Tuist는 의존성 그래프의 각 타겟에 대해 <.localized_link href="/guides/features/projects/hashing">해시를 효율적으로 활용</.localized_link>하여 변경 사항을 감지합니다. 이 데이터를 활용하여 이러한 타겟에서 파생된 바이너리를 빌드하고 고유 식별자를 할당합니다. 그래프 생성 시 Tuist는 원래 타겟을 해당 바이너리 버전으로 원활하게 대체합니다.

이 작업은 *"워밍업"* 이라고 하며, 로컬 사용 또는 팀원 및 CI 환경과 Tuist를 통해 공유하기 위한 바이너리를 생성합니다. 캐시 워밍업 과정은 간단하며 다음 명령어로 시작할 수 있습니다:

```bash
tuist cache
```

이 명령어는 프로세스 속도를 높이기 위해 바이너리를 재사용합니다.

바이너리 업로드에 실패하면 명령어는 나머지 바이너리는 계속 업로드한 후 종료 상태 코드가 0이 아닌 상태로 종료되고 업로드되지 않은 타겟을 나열합니다. 머신의 로컬 캐시에 있는 바이너리는 캐시된 것으로 간주되므로 같은 머신에서 다시 업로드하려면 워밍업 전에 `tuist clean binaries`을 실행하세요. 바이너리를 로컬 캐시에만 저장하려면 `--no-upload`를 전달하세요.

### 대상 선택 {#destination-selection}

하나의 대상에 대해 캐시하고 생성하려면 `--destination simulator` 또는 `--destination device`를 사용하세요:

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

기본값은 `all`이며, Mac Catalyst를 포함하여 타겟이 지원하는 모든 대상을 보존합니다. 이후의 `tuist cache`는 캐시된 슬라이스를 재사용하고 누락된 SDK만 빌드합니다. 일반 생성은 필요한 슬라이스가 누락된 경우 모듈의 소스를 유지합니다.

제한된 생성은 소스 타겟을 선택한 대상으로 제한하고 매크로를 포함한 네이티브 macOS 타겟을 보존합니다. 제한 모드 모두 Mac Catalyst를 포함하지 않습니다. 모든 대상을 복원하려면 `--destination all`로 다시 생성하세요.

슬라이스별 캐싱은 표준 아키텍처를 사용하는 iOS 및 macOS를 지원합니다. 기타 플랫폼, 사용자 정의 아키텍처 및 지원되지 않는 제품은 전체 아티팩트 캐싱을 유지합니다. 레거시 모듈 캐싱에는 `--destination all`이 필요합니다.

### 원격 업로드 승인 {#remote-upload-admission}

최신 모듈 캐싱은 REAPI를 사용합니다. 바쁜 캐시가 `RESOURCE_EXHAUSTED`로 업로드를 일시적으로 거부하면 Tuist는 지터를 적용하여 백오프하고, 표준 `google.rpc.RetryInfo` 최소 지연 시간을 준수하며, 제한된 대기 예산 내에서 재시도합니다. 업로드 승인은 호출당 최대 6번의 재시도를 허용합니다. 각 블롭 업로드 작업은 존재 확인, 일괄 업로드 및 스트리밍 쓰기 전반에 걸쳐 단일 60초 누적 백오프 예산을 공유합니다. 동시 대기는 각각 예산을 소비하므로 반복적인 거부는 큐에 있는 모든 블롭에 추가 재시도 시간을 부여하지 않습니다. 성공적인 전송은 이 예산을 소비하지 않으며 예산이 소진되어도 취소되지 않습니다. 액션 결과 게시에는 자체 제한 예산이 있습니다. 지수적 지연은 1초부터 시작하여 비례 지터 전에 30초까지 증가합니다. 서버의 필수 지연 시간이 남은 예산을 초과하면 Tuist는 지시보다 일찍 재시도하는 대신 실패합니다. 취소는 백오프를 중단하며, 캐시 읽기는 과부하로 인해 생성이 중단되지 않도록 짧은 재시도를 유지합니다.

이러한 기본값은 재시도 힌트가 없는 이전 Kura 버전에도 도움이 됩니다. 더 긴 재시도는 지속적인 과부하가 아닌 일시적인 경합을 흡수합니다. 거부가 지속되면 웜 잡의 [캐시 동시성 제한](#cache-concurrency-limit)을 줄이거나 서버 용량을 늘리세요. Pod 메모리 추정치 및 승인 메트릭은 [Kura 업로드 크기 조정](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)을 참조하세요.

### 구성 선택 {#configuration-selection}

`--configuration`를 전달하지 않고 캐시를 워밍업할 때 Tuist는 다음 순서로 사용할 빌드 구성을 선택합니다:

1. 매니페스트의 `Project.Options.generationOptions`에 설정된 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)(있는 경우).
2. 그렇지 않으면 이름순으로 정렬된 `debug` 변형의 첫 번째 빌드 구성.

특정 구성에 대한 캐시를 워밍업하려면 명시적으로 전달하세요:

```bash
tuist cache --configuration Release
```

## 사용법 {#usage}

기본적으로 Tuist 명령어가 프로젝트 생성을 필요로 할 때 사용 가능한 경우 종속성을 캐시의 바이너리 등가물로 자동으로 대체합니다. 또한 특정 타겟 목록을 지정하면 Tuist는 사용 가능한 경우 종속 타겟도 캐시된 바이너리로 대체합니다. 다른 접근 방식을 선호하는 경우 특정 플래그를 사용하여 이 동작을 완전히 옵트아웃할 수 있는 옵션이 있습니다:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> 바이너리 캐싱은 시뮬레이터나 장치에서 앱을 실행하거나 테스트를 실행하는 것과 같은 개발 워크플로우를 위해 설계된 기능입니다. 릴리스 빌드를 위한 것이 아닙니다. 앱을 아카이브할 때는 `--cache-profile none`를 사용하여 소스와 함께 프로젝트를 생성하세요.

## 캐시 프로필 {#cache-profiles}

Tuist는 프로젝트 생성 시 타겟이 캐시된 바이너리로 얼마나 적극적으로 대체될지를 제어하기 위해 캐시 프로필을 지원합니다.

- 내장:
  - `only-external`: 외부 종속성만 대체(시스템 기본값)
  - `all-possible`: 가능한 많은 타겟 대체(내부 타겟 포함)
  - `none`: 캐시된 바이너리로 절대 대체하지 않음

`tuist generate`에서 `--cache-profile`로 프로필을 선택하세요:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **사용 중단된 플래그**
>
> `--no-binary-cache` 플래그는 사용 중단되었습니다. 대신 `--cache-profile none`를 사용하세요. 사용 중단된 플래그는 하위 호환성을 위해 여전히 작동합니다.

효과적인 동작을 해결할 때의 우선순위(높음에서 낮음):

1. `--cache-profile none`
2. 타겟 포커스(`generate`에 타겟 전달) → 프로필 `all-possible`
3. `--cache-profile <value>`
4. 구성 기본값(설정된 경우)
5. 시스템 기본값(`only-external`)

## 지원되는 제품 {#supported-products}

다음 타겟 제품만 Tuist에서 캐시할 수 있습니다:

- 프레임워크(정적 및 동적), [XCTest](https://developer.apple.com/documentation/xctest) 또는 Swift Testing에 의존하는 테스트 지원 프레임워크 포함
- 라이브러리(정적 및 동적), XCTest 또는 Swift Testing에 의존하는 테스트 지원 라이브러리 포함
- 번들
- Swift 매크로

테스트 번들은 모듈 캐시에서 제외됩니다. 즉, `unitTests` 및 `uiTests` 타겟은 바이너리로 캐시되지 않지만, 테스트가 의존하는 일반 프레임워크 및 라이브러리 타겟은 XCTest 또는 Swift Testing을 링크하더라도 캐시될 수 있습니다.

캐시된 라이브러리 `.xcframework`는 생성된 프로젝트가 이를 가져오는 데 필요한 메타데이터를 보존합니다. 소스 타겟이 공개 헤더를 선언하는 경우 Swift 모듈과 공개 C/Objective-C 헤더도 포함됩니다.

> [!NOTE]
> **상위 종속성**
>
> 타겟이 캐시 불가능하면 상위 타겟도 캐시 불가능해집니다. 예를 들어, A가 B에 의존하는 종속성 그래프 `A > B`가 있을 때, B가 캐시 불가능하면 A도 캐시 불가능해집니다.

## 분석 {#analytics}

프로젝트 대시보드에서 **모듈 캐시 → 모듈**을 열어 자주 미스가 발생하는 모듈을 찾으세요. 개선하려는 환경(예: **CI**)과 날짜 범위를 선택하세요. 개요에는 캐시 히트, 미스 및 미스가 발생한 모듈이 표시됩니다. 모듈을 열면 해당 기록과 각 관찰에 할당된 이유가 표시됩니다.

**미스** 드롭다운은 하나의 이유에 대한 개수와 설명을 선택합니다. 차트는 네 가지 이유의 분포를 보여줍니다. 모듈 페이지에서 기록의 **이유** 필터를 사용하여 개별 발생 사항을 검사하세요. 정의는 이유 배지에 마우스를 올리거나 키보드로 포커스하여 확인할 수 있습니다.

### 미스 이유 {#miss-reasons}

| 이유 | 의미 |
| --- | --- |
| **변경됨** | 모듈 자체의 비교 입력이 변경되었습니다. 여기에는 파일 해시, 빌드 설정, 해결된 구성 및 컴파일러 식별자가 포함됩니다. 소스 편집은 가능한 원인 중 하나일 뿐입니다. |
| **상위** | 모듈 자체의 비교 입력은 동일하게 유지되었지만, 종속성 또는 외부 패키지 해시가 변경되었습니다. 모듈의 소스 파일은 변경되지 않았을 수 있습니다. |
| **콜드** | 비교할 이전 모듈 관찰이 없거나, 보고된 입력이 미스를 설명하지 않으며, 이전 원격 가용성에 대한 적절한 증거가 없습니다. 콜드는 모듈이 한 번도 캐시되지 않았음을 증명하지 않습니다. |
| **제거됨** | 정확한 캐시 키가 이전에 동일한 프로젝트의 동일한 기록된 캐시 엔드포인트에서 원격 히트를 기록했지만, 지금은 미스됩니다. |

**제거됨**으로 표시된 미스의 경우, 아티팩트는 이전에 원격 캐시에서 다운로드되었지만 이번에는 재사용할 수 없었습니다. 제거가 가장 유력한 원인이지만, 접근 또는 다운로드 실패도 미스를 설명할 수 있습니다. Tuist는 이전 원격 히트를 찾았을 때만 이 라벨을 할당합니다. 이전 미스와 로컬 히트는 충분하지 않습니다.

예를 들어:

| 시나리오 | 분류 |
| --- | --- |
| 이전 관찰이나 적절한 원격 히트 없이 모듈이 미스됨 | 콜드 |
| A가 변경됨; B는 A에 의존하고 C는 B에 의존함; 세 키 모두 변경됨 | A는 변경됨; B와 C는 상위 |
| 소스와 설정은 변경되지 않은 상태에서 워밍업 후 컴파일러 버전이 변경됨 | 두 관찰 모두 컴파일러 입력을 보고하면 영향을 받은 미스는 변경됨으로 분류됨 |
| 정확한 키가 원격에서 다운로드된 후 아티팩트가 제거되어 미스됨 | 이전 히트가 증거로 자격이 있는 경우 제거됨 |
| 키가 반복적으로 미스되고 성공적으로 워밍업된 적이 없음 | 콜드로 남을 수 있음 |

이유는 관찰 결과를 설명하며, 키에 영구적으로 부착된 라벨이 아닙니다. 예를 들어, 컴파일러 업그레이드 후 첫 번째 미스는 변경됨으로 분류될 수 있지만, 해당 새 키에 대한 이후 미스가 원격에서 사용 가능한 것으로 관찰된 적이 없다면 콜드로 분류될 수 있습니다.

### 캐시 히트율 개선 {#improving-cache-hit-rate}

1. **일관된 기준을 선택하세요.** CI와 대표적인 날짜 범위로 시작하세요. 모듈을 미스 횟수 기준으로 정렬한 후, 히트율, 종속 대상 및 빌드 비용을 고려하세요. 자주 미스되는 비용이 큰 종속성을 수정하는 것이 작은 모듈의 히트율을 개선하는 것보다 더 많은 시간을 절약할 수 있습니다. 변경 후 동일한 환경과 유사한 워크로드를 비교하세요.
2. **변경됨 미스를 조사하세요.** 관련 실행을 열고 전체 키와 보고된 입력을 비교하세요. 워밍업 작업과 소비 작업을 의도한 Xcode/컴파일러 버전, 구성 및 타겟 대상에 맞추세요. 의도적인 변경 후에는 다시 워밍업하세요. 변동성이 큰 생성 파일이나 환경 의존적 설정으로 인해 안정적이었던 모듈이 무효화된다면 해당 입력을 조사하세요. 바이너리 호환성에 영향을 미치는 입력은 해시에 포함하세요.
3. **상위 미스를 따라 변경된 종속성을 찾으세요.** 직접적인 변경 사항을 찾기 위해 해당 기록을 검사하세요. 결과 키를 워밍업하면 재사용을 복원할 수 있습니다. 자주 변경되는 구현이 많은 비용이 드는 종속 항목을 무효화한다면, [효율성](#efficiency)에서 설명한 대로 더 작은 모듈이나 안정적인 인터페이스를 고려하세요.
4. **콜드 미스에 대한 워밍업 범위를 확인하세요.** 워밍업이 필요한 모듈을 선택하고, 소비 작업의 구성과 환경을 사용하며, 아티팩트를 성공적으로 업로드하는지 확인하세요. 실제 CI 작업에서 사용되는 전체 키를 확인하세요. 워밍업과 소비가 서로 다른 키를 요청한다면, 캐시가 제거되었다고 가정하기 전에 해싱 입력을 검사하세요. 모듈의 소스가 변경되지 않았더라도 이전 성공적인 업로드 없이 반복적으로 미스될 수 있습니다.
5. **제거됨 미스에 대한 증거를 활용하세요.** 소비 실행의 키와 엔드포인트를 확인한 후, 소비 실행의 캐시 경고와 워밍업 작업의 업로드 결과를 검사하세요. 해당되는 경우 보존 또는 제거 상태를 확인하세요. 필요한 아티팩트를 다시 워밍업하고 후속 히트를 확인하세요. 여전히 미스된다면 관련 실행 링크와 로그를 지원 팀과 공유하세요.

해시 비교를 위해, 워밍업하고 소비하려는 구성을 사용하여 각 관련 환경에서 다음을 실행하세요:

```bash
tuist hash cache --configuration Debug --verbose
```

모듈의 전체 해시와 구성 요소 블록을 비교하세요. 변경되지 않은 동일한 머신에서 명령을 반복하면 일반적으로 동일한 결과가 나와야 합니다. 불일치를 조사하려면 실제 워밍업 환경과 소비 환경을 비교하세요. 두 명령 모두 캐시를 히트할 필요가 없습니다. 추가 확인 사항은 <.localized_link href="/guides/features/projects/hashing#debugging">해싱 진단</.localized_link>을 참조하세요.

## 효율성 {#efficiency}

바이너리 캐싱으로 달성할 수 있는 효율성 수준은 그래프 구조에 크게 의존합니다. 최상의 결과를 얻기 위해 다음을 권장합니다:

1. 매우 깊게 중첩된 종속성 그래프는 피하세요. 그래프가 얕을수록 좋습니다.
2. 구현 타겟 대신 프로토콜/인터페이스 타겟으로 종속성을 정의하고, 최상위 타겟에서 구현을 종속성 주입하세요.
3. 자주 수정되는 타겟을 변경 가능성이 낮은 더 작은 타겟으로 분할하세요.

위의 제안 사항은 <.localized_link href="/guides/features/projects/tma-architecture">모듈식 아키텍처</.localized_link>의 일부이며, 이는 바이너리 캐싱뿐만 아니라 Xcode 기능의 이점을 최대화하기 위해 프로젝트를 구조화하는 방법으로 제안됩니다.

## 권장 설정 {#recommended-setup}

캐시를 워밍업하기 위해 **main 브랜치의 모든 커밋에서 실행**되는 CI 작업을 갖추는 것을 권장합니다. 이렇게 하면 캐시에 항상 `main`의 변경 사항에 대한 바이너리가 포함되어 있어 로컬 및 CI 브랜치 빌드가 이를 기반으로 증분 빌드될 수 있습니다.

> [!TIP]
> **캐시 워밍업을 격리하세요**
>
> 생성된 워크스페이스에 의존하는 후속 단계 없이 전용 CI 단계에서 `tuist cache`를 실행하세요. `tuist cache`는 캐시 빌드를 위해 워크스페이스를 수정하므로, 워크스페이스가 필요한 CI 단계는 먼저 `tuist generate`를 실행하여 새로 사용 가능한 워크스페이스를 가져와야 합니다.

> [!TIP]
> **캐시 워밍업은 바이너리를 사용합니다**
>
> `tuist cache` 명령은 또한 워밍업 속도를 높이기 위해 바이너리 캐시를 사용합니다.

다음은 일반적인 워크플로우의 몇 가지 예입니다:

### 개발자가 새 기능 작업을 시작함 {#a-developer-starts-to-work-on-a-new-feature}

1. `main`에서 새 브랜치를 생성합니다.
2. `tuist generate`를 실행합니다.
3. Tuist는 `main`에서 최신 바이너리를 가져와 프로젝트로 생성합니다.

### 개발자가 변경 사항을 상류로 푸시함 {#a-developer-pushes-changes-upstream}

1. CI 파이프라인은 프로젝트를 빌드하거나 테스트하기 위해 `xcodebuild build` 또는 `tuist test`를 실행합니다.
2. 워크플로우는 `main`에서 최신 바이너리를 가져와 프로젝트로 생성합니다.
3. 그런 다음 프로젝트를 증분 방식으로 빌드하거나 테스트합니다.

## 구성 {#configuration}

### 캐시 동시성 제한 {#cache-concurrency-limit}

다운로드와 업로드를 모두 제한하려면 `TUIST_CACHE_CONCURRENCY_LIMIT`를 양의 정수로 설정하세요. 예를 들어, 워밍 작업에서 작은 자체 호스팅 캐시의 부하를 줄입니다:

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

설정되지 않은 경우 REAPI 업로드는 8개의 전송 작업을 사용합니다. 다운로드는 Blob이 ByteStream을 필요로 할 때 8개를 사용하고, 배치 전용 플랜의 경우 32개를 사용합니다. 레거시 HTTP 캐시 경로의 기본값은 100이며, 이 기본값은 REAPI에 적용되지 않습니다. 이전에 문서화된 `none`를 포함한 잘못된 값은 제한을 제거하는 대신 기본값을 유지합니다. 기본값을 복원하려면 `unset TUIST_CACHE_CONCURRENCY_LIMIT`를 사용하세요.

제한은 작업 또는 CI 작업 전체에 글로벌하게 적용되는 것이 아니라 전송 작업마다 적용됩니다. 제한이 2인 상태에서 동시에 3개의 워밍업이 진행되면 동일한 캐시에 대해 6개의 업로드가 활성화될 수 있습니다. 소비자 작업은 변수를 설정하지 않은 상태로 두어 기본 다운로드 병렬 처리를 유지할 수 있습니다.

### 캐시 워밍업 임시 디렉터리 {#cache-warm-scratch-directory}

기본적으로 `tuist cache`는 빌드 중간 파일과 조립된 캐시 아티팩트를 위한 임시 임시 디렉터리를 생성한 후, 캐시 워밍업이 완료되면 이를 제거합니다. 이러한 파일을 사용자가 관리하는 디렉터리 아래에 유지하려면 `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`를 설정하세요.

경로는 절대 경로이거나 현재 작업 디렉터리에 상대적일 수 있습니다. Tuist는 디렉터리가 존재하지 않으면 생성합니다. 이미 존재하는 경우 빈 디렉터리여야 합니다.

이 환경 변수가 설정되면 Tuist는 명령이 완료된 후에도 디렉터리와 해당 내용을 그대로 유지합니다. 호출자는 다음 캐시 워밍업 전에 이를 정리할 책임이 있습니다. 변수가 설정되지 않으면 Tuist는 임시 디렉터리를 계속 사용하고 제거합니다.

외부 빌드 타겟을 워밍업해야 할 경우 Tuist는 호출자가 소유한 임시 디렉터리를 거부합니다. 외부 빌드 스크립트는 자체 출력 위치를 제어하므로 Tuist는 해당 출력이 임시 디렉터리 내에 유지되도록 보장할 수 없습니다.

### 코드 커버리지 {#code-coverage}

> [!NOTE] EARLY ACCESS
> 모듈 캐시를 사용한 코드 커버리지는 얼리 액세스 단계입니다. `TUIST_FEATURE_FLAG_COVERAGE=1`가 설정된 경우에만 아래에 설명된 계측된 바이너리를 읽고 워밍업합니다.

모듈 캐시의 타겟은 미리 빌드된 바이너리이며, 테스트 실행은 해당 바이너리가 커버리지 카운터로 빌드된 경우에만 코드를 측정합니다. `Tuist.swift`에서 프로젝트의 커버리지를 켜세요:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

`enabled`를 사용하면 모든 명령과 환경이 프로젝트 자체 타겟에 대해 캐시의 하나의 계측된 변형을 읽으므로, CI에서의 단일 워밍업으로 CI와 로컬 머신 모두에 제공됩니다:

| 명령 | 프로젝트의 타겟 | 외부 패키지 |
| --- | --- | --- |
| `tuist cache` (Debug 구성) | 계측된 바이너리 워밍업 | 일반 바이너리 워밍업 |
| `tuist cache` (Release 구성) | 일반 바이너리 워밍업 | 일반 바이너리 워밍업 |
| `tuist hash cache` | 계측된 키 출력 | 일반 키 출력 |
| `tuist generate` | 계측된 바이너리 읽기 | 일반 바이너리 읽기 |
| `tuist test` | 계측된 바이너리 읽기 | 일반 바이너리 읽기 |

이 옵션은 Xcode가 Debug로 취급하는 모든 구성에 적용됩니다. Release 빌드는 절대 계측되지 않습니다. Tuist는 또한 해당 구성에서 프로파일 런타임을 링크하므로(`CLANG_COVERAGE_MAPPING_LINKER_ARGS`), 커버리지를 수집하지 않는 빌드도 여전히 계측된 바이너리를 링크하며, 자동으로 생성하는 스킴과 `coverage`를 설정하지 않고 정의한 스킴의 테스트 액션에서 커버리지를 켭니다.

직접 정의한 스킴은 자체적으로 커버리지를 설정하지 않는 한 옵션을 따릅니다. `.options(coverage: false)`는 꺼진 상태로 유지하고 `.options(coverage: true)`는 옵션이 무엇이든 켜진 상태로 유지합니다. 테스트 플랜은 자체적으로 커버리지를 결정하며, `-enableCodeCoverage`는 Xcode에서와 마찬가지로 실행을 여전히 덮어씁니다. 커버리지를 수집하지 않고 계측된 바이너리를 읽는 실행은 정상적으로 빌드하고 테스트합니다. 실행이 커버리지를 수집하지만 프로젝트의 타겟이 일반 바이너리로 캐시에서 가져온 경우, Tuist는 해당 커버리지가 측정되지 않았다고 경고합니다.

`TUIST_COVERAGE_ENABLED` 환경 변수(`1` 또는 `0`)는 `coverage: .coverage(enabled:)`보다 우선합니다. 캐시를 워밍업하는 명령과 읽는 명령이 일치하도록 단일 명령이 아닌 CI 워크플로와 같은 전체 환경에 대해 설정하세요.

`prefixMapping` (<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 캐시</.localized_link> 참조)에는 자체 재정의가 있습니다. `TUIST_COVERAGE_PREFIX_MAPPING` 환경 변수(`1` 또는 `0`)는 `coverage: .coverage(prefixMapping:)`보다 우선합니다.

꺼짐으로 재정의하면 일반 변형을 읽으며, 커버리지를 켠 상태로 워밍업된 캐시는 이를 채우지 않으므로 해당 타겟은 소스에서 빌드됩니다. Release 워밍업은 항상 일반 바이너리를 워밍업합니다.

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled`와 `prefixMapping`는 프로젝트 타겟의 빌드 설정과 캐시 키, 그리고 테스트 타겟의 선택적 테스트 해시를 변경합니다. 캐시를 공유하는 모든 머신에서 동일한 값으로 설정하고 환경(예: `Environment.isCI`)에서 파생하지 마세요. CI와 로컬 머신 간에 값이 다르면 서로 다른 키가 생성됩니다. 환경 변수도 마찬가지입니다. `TUIST_COVERAGE_ENABLED=0`로 실행하면 커버리지를 켠 실행의 바이너리나 선택적 테스트 결과를 재사용하지 않습니다.

다음 사항을 유의하세요:

- 계측된 바이너리는 더 큽니다. 정적 아카이브와 동적 라이브러리의 경우 약 20~30% 더 큽니다. Debug 빌드는 동일한 속도로 실행됩니다.
- Xcode의 커버리지 보고서는 이 옵션 사용 여부와 관계없이 캐시에서 가져온 코드를 절대 표시하지 않습니다. Tuist의 커버리지 업로드가 이를 측정합니다. Xcode에서 타겟의 커버리지를 보려면 `tuist generate <target>`로 포커스를 맞춰 소스에서 빌드되도록 하세요.

## 문제 해결 {#troubleshooting}

### 내 타겟에 바이너리를 사용하지 않음 {#it-doesnt-use-binaries-for-my-targets}

환경과 실행 간에 <.localized_link href="/guides/features/projects/hashing#debugging">해시가 결정론적</.localized_link>인지 확인하세요. 이는 프로젝트가 절대 경로 등을 통해 환경을 참조할 때 발생할 수 있습니다. `diff` 명령을 사용하여 `tuist generate`의 두 번 연속 호출로 생성된 프로젝트를 비교하거나 환경 또는 실행 간에 비교할 수 있습니다.

또한 타겟이 <.localized_link href="/guides/features/cache/module-cache#supported-products">캐시 불가능한 타겟</.localized_link>에 직접적이거나 간접적으로 의존하지 않는지 확인하세요.

### 누락된 심볼 {#missing-symbols}

소스를 사용할 때 Xcode의 빌드 시스템은 Derived Data를 통해 명시적으로 선언되지 않은 종속성을 해결할 수 있습니다. 그러나 바이너리 캐시에 의존할 때는 종속성을 명시적으로 선언해야 합니다. 그렇지 않으면 심볼을 찾을 수 없어 컴파일 오류가 발생할 가능성이 높습니다. 이를 디버그하려면 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 명령을 사용하고 CI에서 설정하여 암시적 링크의 회귀를 방지하는 것을 권장합니다.
