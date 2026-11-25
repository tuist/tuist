---
{
  "title": "러너",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너는 GitHub Actions, Buildkite, GitLab CI 및 Bitrise용 관리형 macOS 및 Linux 러너로, 컴퓨팅 환경과 동일한 위치에 캐시가 배치되어 로컬 머신과 공유됩니다."
}
---
# Runners {#runners}

Tuist Runners는 GitHub Actions, Buildkite, GitLab CI, Bitrise 파이프라인을 위한 관리형 macOS 및 Linux 러너입니다. CI 제공업체의 호스팅 머신에서 작업을 실행하는 대신, Tuist <.localized_link href="/guides/features/runners/profiles">프로파일</.localized_link>을 지정하면 Tuist의 플릿에서 실행되며, 팀이 이미 사용하는 동일한 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에서 동작합니다. 설치해야 하는 러너 에이전트나 유지보수해야 할 인프라가 없습니다. 머신을 변경하기 전에 CI 비용에 영향을 주는 요인을 파악하려면 [CI 비용](https://tuist.dev/solutions/ci-costs)을 참조하세요.

도입은 일반적으로 작업에 한 줄 변경만으로 가능합니다.

::: code-group

```diff [GitHub Actions]
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

```diff [Buildkite]
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```
<!-- -->
:::

## Linux에서의 Android 에뮬레이터 {#android-emulators}

Linux 러너는 기본적으로 `/dev/kvm`를 통해 하드웨어 가속 가상화를 제공합니다. Gradle Managed Devices를 포함하여 x86_64 Android 에뮬레이터를 실행하려면 일반적인 Linux <.localized_link href="/guides/features/runners/profiles">프로파일</.localized_link>(예: `tuist-linux`)을 사용하세요. 디바이스에 접근하기 위해 특별한 러너 프로파일, KVM 설정 액션, 권한 변경 또는 `sudo`가 필요하지 않습니다.

러너 이미지에는 Android SDK가 포함되어 있습니다. 디바이스를 시작하기 전에 에뮬레이터와 런타임 라이브러리를 설치하세요. `pixel6`라는 이름의 Gradle Managed Device를 이미 정의한 프로젝트의 경우, GitHub Actions 작업은 다음과 같습니다.

```yaml
jobs:
  android-test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install emulator dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            libx11-6 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 \
            libxrender1 libpulse0 libnss3 libxkbcommon-x11-0 libxcb-cursor0 \
            libasound2 libglu1-mesa
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'emulator'
      - name: Check hardware acceleration
        run: |
          test -r /dev/kvm && test -w /dev/kvm
          "$ANDROID_HOME/emulator/emulator" -accel-check
      - name: Run instrumented tests
        run: ./gradlew :app:pixel6DebugAndroidTest
```

Android Gradle Plugin에서 요구하는 Java 버전을 사용하고, 테스트 태스크를 프로젝트의 managed-device 태스크로 교체하세요. **x86_64** 시스템 이미지를 구성하세요. Gradle과 에뮬레이터 모두를 수용할 충분한 메모리를 갖춘 러너 셰이프를 선택하세요. 동시에 실행되는 디바이스는 해당 작업의 CPU 및 메모리 할당량을 공유합니다.

일반 러너 사용자로 에뮬레이터를 실행하세요. 이 예제에서 `sudo`는 운영 체제 패키지를 설치하는 용도로만 사용됩니다.

에뮬레이터는 중첩 가상화를 사용하므로 타이밍이 실제 Android 디바이스와 다를 수 있습니다. 에뮬레이터 벤치마크는 실제 디바이스 성능이 아닌 해당 CI 환경의 측정값으로 간주하세요.

## 동시성 제한 {#concurrency-limits}

각 계정은 macOS와 Linux에 대해 독립적인 vCPU 및 메모리 동시성 제한을 가집니다. Tuist가 작업을 승인하기 전에, 해당 플랫폼에서 현재 실행 중인 모든 작업과 비교하여 작업의 <.localized_link href="/guides/features/runners/profiles#machine-shapes">머신 셰이프</.localized_link>를 확인합니다. 작업의 vCPU와 메모리가 남은 용량 내에 맞을 때만 작업이 시작되며, 그렇지 않으면 용량이 확보될 때까지 큐에 대기합니다. 한 플랫폼에서의 작업은 다른 플랫폼의 용량을 소모하지 않습니다.

Air 계정은 고정된 동시성 제한을 가집니다. Pro 및 Enterprise 계정은 표준 macOS 작업 6개(48 vCPU / 144 GB)와 Linux에서 64 vCPU / 128 GB로 시작하며, Tuist는 반복적인 사용량과 활성 러너와 함께 실행될 수 없는 최근 큐잉된 작업을 기반으로 자동으로 여유 용량을 추가합니다. 제한이 낮은 동안(최대 표준 macOS 작업 12개 또는 Linux에서 128 vCPU / 512 GB)에는 시간당 최대 한 번까지 모든 큐잉된 작업을 수용하도록 증가할 수 있습니다. 그 이상에서는 안전 상한선까지 하루에 최대 한 번,每次 최대 50%씩 증가하므로 갑작스러운 급증이 무제한 동시성을 부여하지는 않습니다. 자동 조정은 제한을 증가시키기만 합니다. 기존 할당량과 계약상 최소 용량은 유지됩니다. 더 높은 계정 제한이 즉시 사용 가능한 머신을 보장하지는 않습니다.

Runners 대시보드의 **Concurrency** 섹션은 시간별 허용된 최대 vCPU 및 메모리 사용량을 표시하며, 각 시간 시작 시점에 알려진 제한 값을 계단식 선으로 나타냅니다. 빨간색 막대는 해당 역사적 임계값에 도달했음을 의미하며, 이것만으로 작업이 대기했음을 증명하지는 않습니다. 한 시간 동안의 증가는 피크 값을 버킷 시작 선보다 높게 만들 수 있습니다. 현재 제한은 각 차트 옆에 표시됩니다. 기록 추적이 시작되기 전 기간은 가정된 역사적 값 대신 제한 선이 표시되지 않습니다.

워크플로우가 안전 상한선에서 계속 큐에 대기한다면, 필요한 용량을 검토할 수 있도록 계정 핸들, 플랫폼 및 예상 병렬 작업량을 포함하여 [문의해 주세요](mailto:contact@tuist.dev).

## 네트워크 액세스 {#network-access}

작업은 공인 인터넷으로 아웃바운드 연결을 열 수 있습니다. 사설 주소 범위(`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)는 차단되며, 러너는 인바운드 연결을 허용하지 않습니다.

| 플랫폼 | 아웃바운드 포트 |
| --- | --- |
| Linux | TCP 22(SSH), 80(HTTP), 443(HTTPS) 및 DNS |
| macOS | 모든 포트 |

SSH는 `git@` 의존성, SSH 서브모듈, 배포 키 및 `ssh` 또는 `scp` 배포를 포함합니다. Linux 워크플로우에서 다른 아웃바운드 포트가 필요하면 [문의해 주세요](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub를 연결하고 runs-on을 Tuist 프로파일로 지정한 후 플릿에서 첫 번째 작업을 실행하세요."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="클러스터를 연결하고 Tuist 프로파일 이름을 따서 큐를 명명한 후 단계에서 타겟팅하세요."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab을 한 번 연결하고 파이프라인 태그로 각 작업의 머신을 선택하세요."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="워크스페이스를 연결하고 셀프호스팅 러너 풀의 빌드를 Tuist 프로파일에서 실행하세요."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="자체 git 포지 또는 오케스트레이터에서 한 번의 요청으로 작업을 실행하고 웹훅으로 추적하세요."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiles"
    details="작업에서 참조하는 이름 지정 머신 프로파일로 플랫폼, 크기 및 Xcode 버전을 선택하세요."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Images"
    details="macOS 및 Linux 러너에 사전 설치된 내용을 확인하세요: Xcode, 시뮬레이터, Metal 툴체인, Docker, Android SDK 등."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Cache volumes"
    details="Xcode, 모듈 및 Gradle 캐시와 기타 디렉터리를 작업 간에 유지하며, 각 실행마다 개인용 쓰기 가능 복사본을 제공합니다."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo 그래프 작업 {#struo-graph-actions}

<a id="once-graph-actions"></a>

계정에 원격 실행이 활성화되어 있고 서버가 호환되는 워커 기능을 광고할 때, Struo는 Tuist의 Linux 워커에서 적격 그래프 명령 작업을 실행할 수 있습니다. 이는 위의 CI 제공자 작업과 별개인 작업 수준 실행입니다. 설정, 이미지 요구 사항 및 호환성 검사는 <.localized_link href="/guides/features/runners/struo">Struo 원격 실행</.localized_link>을 참조하세요.

## Tuist Runners를 사용하는 이유 {#why-tuist-runners}

대부분의 CI 러너 제공업체는 더 강력한 머신과 영구 캐시(일반적으로 CI 실행에 다시 마운트되는 공유 볼륨)를 제공하여 작업을 빠르게 만듭니다. 도움이 되지만 볼륨은 단순히 디스크일 뿐이며 이전 CI 실행이 남긴 모든 것을 포함합니다. 빌드가 실행되는 위치에 가장 최신 아티팩트만 가깝게 유지하도록 복제되지 않으며, 코드가 빌드되는 다른 위치에는 전혀 도달하지 않습니다.

빌드는 더 이상 한 곳에서 발생하지 않습니다. 동일한 코드는 개발자 노트북, CI 전반, 그리고 점점 더 코딩 에이전트 및 기타 자동화 환경에서 컴파일됩니다. Tuist Runners는 사용하는 빌드 시스템에 관계없이 모든 환경이 이미 읽고 쓰는 동일한 <.localized_link href="/guides/features/cache">캐시</.localized_link>를 공유하기 때문에 다릅니다. 팀원이 노트북에서 워밍업한 아티팩트, 에이전트가 생성한 아티팩트 또는 이전 빌드가 남겨둔 아티팩트는 러너에서 히트로 처리되며 그 반대도 마찬가지입니다. 별도로 워밍업해야 하는 CI 캐시가 없으며 속도 향상은 CI에만 국한되지 않습니다.

또한 캐시는 러너와 동일한 사설 네트워크에 공동 배치되므로 캐시 읽기 및 쓰기가 공인 인터넷을 통과하는 대신 내부에 머물며 컴퓨팅 리소스와 가까운 상태에서 수행됩니다.

종합하면 다음과 같습니다:

- **모든 환경에서 공유.** 러너는 개발자 머신, CI 및 코딩 에이전트와 동일한 캐시를 읽고 쓰므로 어디서든 수행된 작업이 모든 곳의 캐시를 워밍업합니다.
- **컴퓨팅 리소스와 공동 배치.** 캐시 트래픽은 공인 인그레스를 통하지 않고 러너 옆의 내부 네트워크에 머물릅니다.
- **별도 추가가 아닌 단일 시스템.** 캐싱, <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>, <.localized_link href="/guides/features/test-sharding">테스트 샤딩</.localized_link> 및 <.localized_link href="/guides/features/build-insights">빌드 인사이트</.localized_link>가 모두 동일한 프로젝트 및 계정을 대상으로 실행되므로 러너는 별도의 빌드 데이터 실로가 아닙니다.
