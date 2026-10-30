---
{
  "title": "Rust cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Reuse supported Rust compilation outputs locally and through Tuist's remote cache with Cargo."
}
---
# Rust 캐시 {#rust-cache}

Tuist는 지원되는 Rust 컴파일 결과물을 캐시하여, 빌드 결과물이 제거된 후에도 Cargo가 이를 재사용할 수 있도록 합니다. 이 캐시는 Tuist CLI에 내장되어 있습니다. 별도의 캐시 실행 파일이나 Cargo 플러그인을 설치할 필요가 없습니다.

> [!WARNING] Experimental compilation cache
> 현재 버전은 레지스트리 리프 라이브러리만 캐시합니다. 즉, 다른 크레이트에 의존하지 않고 Cargo 레지스트리에서 다운로드한 라이브러리 크레이트만을 의미합니다. 다른 컴파일 작업은 정상적으로 실행됩니다. 캐시 키는 절대 경로와 환경 입력을 포함하므로, 서로 다른 체크아웃 위치 간에서의 재사용은 아직 지원되지 않습니다.

## 캐싱 활성화 {#enable-caching}

프로젝트를 연결하고 인증하려면 <.localized_link href="/guides/get-started/rust-project">Rust 프로젝트 설정</.localized_link> 가이드를 따르세요. 그런 다음 Tuist를 통해 빌드를 실행합니다:

```sh
tuist cargo build --release
```

적격 컴파일 작업에 대해서는 캐싱이 자동으로 수행됩니다. 추가적인 캐시 구성이나 활성화 플래그는 필요하지 않습니다. Tuist는 기존 프로젝트 및 서버 구성을 사용하여 계정의 캐시 엔드포인트를 발견하고 캐시 자격 증명을 획득합니다.

mise를 사용하는 경우, 일반적인 `cargo` 명령어를 계속 입력할 수 있도록 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo 래퍼를 구성</.localized_link>하세요.

## 작동 방식 {#how-it-works}

각 적격 컴파일 작업에 대해 Tuist는 다음과 같이 동작합니다:

1. 로컬 캐시에서 일치하는 결과물을 확인합니다.
2. 로컬 캐시에 없는 경우, Remote Execution API(REAPI)를 통해 Kura에 쿼리하고, 누락된 콘텐츠를 다운로드한 후 복원하기 전에 결과물을 검증합니다.
3. 캐시에 없는 경우, 컴파일러를 정상적으로 실행합니다. 컴파일이 성공하면 결과물을 로컬에 저장하고, 권한이 부여된 경우 REAPI를 통해 Kura에 업로드합니다. 원격 캐시 항목은 참조된 모든 콘텐츠가 사용 가능한 상태가 된 후에만 게시됩니다.

로컬 빌드와 CI 빌드는 동일한 원격 캐시 프로토콜을 사용합니다. 읽기 및 쓰기 접근 권한은 Tuist 서버에서 발급한 캐시 자격 증명과 계정의 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">캐시 업로드 정책</.localized_link>에서 비롯됩니다. 계정은 개발자에게 다운로드를 허용하면서 업로드를 CI 및 계정 토큰으로 제한할 수 있습니다. 캐시 작성자는 신뢰할 수 있는 코드 생성자여야 합니다. 캐시된 컴파일러 출력물은 실행 가능한 코드이므로, 신뢰할 수 있는 머신과 토큰에만 쓰기 권한을 부여하세요.

원격 설정이 실패하더라도 로컬 캐싱은 계속 사용할 수 있습니다. 사용 불가, 누락 또는 손상된 캐시 항목은 컴파일로 대체됩니다. 업로드 실패는 빌드를 실패시키거나 로컬 캐시 항목을 삭제하지 않습니다.

## 캐시 가능한 대상 {#what-can-be-cached}

현재 캐시는 Rust 라이브러리 아티팩트와 이에 수반되는 메타데이터, 종속성 정보, 지원되는 분할 디버그 출력을 생성하는 적격 레지스트리 리프 라이브러리를 지원합니다.

다음 항목들은 여전히 정상적으로 빌드됩니다:

- 다른 크레이트에 의존성이 있는 워크스페이스 크레이트 및 라이브러리.
- 빌드 스크립트, 프로시저럴 매크로 및 이들의 출력물에 의존하는 크레이트.
- 실행 파일, 테스트 바이너리, 네이티브 링크 및 C/C++ 컴파일.
- 증분 컴파일, 사용자 정의 타겟, 지원되지 않는 컴파일러 인수 또는 소스 입력.
- 메타데이터 전용 `cargo check` 호출.
- 렌더링된 진단 정보나 예상치 못한 컴파일러 출력을 내보내는 컴파일.

기존的全局 컴파일러 래퍼는 Tuist의 컴파일 캐시와 컴파일러 옵저버를 비활성화합니다. 사용자 정의 워크스페이스 래퍼도 캐싱을 우회합니다. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">컴파일러 도구 호환성</.localized_link>을 참조하세요.

캐시 키에는 패키지 내용, 컴파일러 및 툴체인, 인수, 작업 디렉터리 및 빌드 환경이 포함됩니다. 자격 증명, Tuist 보고 설정 및 인식된 CI 실행 메타데이터는 항목을 무효화하지 않습니다. 컴파일 중에 이러한 제외된 변수를 읽는 크레이트는 캐시되지 않습니다. 재사용을 테스트할 때 다른 입력과 그 절대 경로를 일관되게 유지하세요. 원격 전송 지원은 서로 다른 체크아웃 경로 간에 출력물을 이동 가능하게 만들지 않습니다.

## 재사용 확인 {#verify-reuse}

Cargo는 이미 최신 상태인 결과물의 재빌드를 피합니다. Cargo의 기존 출력물 대신 Tuist의 캐시를 테스트하려면, 한 번 빌드한 후 Cargo의 출력물을 제거하고 동일한 빌드를 다시 반복하세요:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

두 번째 빌드 시 적격 라이브러리는 복원될 수 있지만, 지원되지 않는 크레이트는 여전히 컴파일됩니다. Cargo의 출력물을 제거해도 Tuist의 별도 로컬 캐시는 제거되지 않습니다. 이는 재사용을 확인하는 것이며, 반드시 원격 다운로드를 의미하는 것은 아닙니다. 로컬 히트는 Kura로부터의 전송이 필요하지 않습니다. 입력 검증과 캐시 작업은 오버헤드를 추가하므로, 작은 크레이트의 경우 컴파일을 피한다고 해서 빌드가 더 빨라진다고 보장할 수는 없습니다.

## 캐시 활동 검사 {#inspect-cache-activity}

프로젝트 대시보드에서 **Cargo Cache**를 열어 히트율, 기록된 전송, 지연 시간, 처리량 및 최근 빌드를 검사하세요. 개별 작업 결정 및 CAS 출력을 확인하려면 빌드의 **Cache** 탭을 엽니다.

누락된 측정은 0으로 계산되지 않으며, 캐시 히트가 반드시 원격 다운로드를 의미하는 것은 아닙니다. 자세한 내용은 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 캐시 측정</.localized_link>을 참조하세요.

## 문제 해결 {#troubleshooting}

캐시 전송 및 보고 실패를 검사하려면 디버그 출력을 활성화하세요:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

히트가 표시되지 않으면, 빌드에 적격한 레지스트리 리프 라이브러리가 포함되어 있는지, 다른 컴파일러 래퍼가 우선권을 차지하고 있지 않은지, 그리고 컴파일러, 플래그, 환경 및 경로가 캐시를 채운 빌드와 일치하는지 확인하세요. 원격 업로드의 경우 인증과 계정의 캐시 업로드 정책도 확인하세요.
