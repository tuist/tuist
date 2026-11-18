---
{
  "title": "러너",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너는 GitHub Actions, Buildkite, GitLab CI, Bitrise를 위한 관리형 macOS 및 Linux 러너로, 컴퓨팅 리소스와 동일한 위치에 캐시가 배치되어 로컬 머신과 공유됩니다."
}
---
# 러너 {#runners}

> [!IMPORTANT]
> **초대 전용**
>
> Tuist Runners는 현재 용량을 확장 중이므로 초대 전용으로 제공됩니다. 계정에 대한 액세스를 요청하려면 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 저희에게 연락하세요. Runners가 일반 공개될 때 가격 정책이 발표됩니다.


Tuist Runners는 GitHub Actions, Buildkite, GitLab CI 및 Bitrise 파이프라인을 위한 관리형 macOS 및 Linux 러너입니다. CI 제공업체의 호스팅 머신에서 작업을 실행하는 대신, Tuist <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>을 지정하여 Tuist의 플릿에서 실행하며, 팀이 이미 사용하는 동일한 <.localized_link href="/guides/features/cache">캐시</.localized_link> 옆에 위치하므로 설치할 러너 에이전트나 유지 관리할 인프라가 필요하지 않습니다.

도입은 일반적으로 작업에 한 줄 변경으로 이루어집니다:

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

## Linux에서 Android 에뮬레이터 {#android-emulators}

Linux 러너는 기본적으로 `/dev/kvm`를 통해 하드웨어 가속 가상화를 제공합니다. 일반적인 Linux <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>(예: `tuist-linux`)을 사용하여 Gradle Managed Devices를 포함한 x86_64 Android 에뮬레이터를 실행하세요. 장치에 액세스하기 위해 특별한 러너 프로필, KVM 설정 액션, 권한 변경 또는 `sudo`가 필요하지 않습니다.

러너 이미지에는 Android SDK가 포함되어 있습니다. 장치를 시작하기 전에 에뮬레이터와 런타임 라이브러리를 설치하세요. `pixel6`라는 이름의 Gradle Managed Device를 이미 정의한 프로젝트의 경우, GitHub Actions 작업은 다음과 같습니다:

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

Android Gradle Plugin에서 요구하는 Java 버전을 사용하고 테스트 작업을 프로젝트의 managed-device 작업으로 교체하세요. **x86_64** 시스템 이미지를 구성하세요. Gradle과 에뮬레이터 모두에 충분한 메모리를 갖춘 러너 셰이프를 선택하세요. 동시에 실행되는 장치는 작업의 CPU 및 메모리 할당량을 공유합니다.

일반 러너 사용자로 에뮬레이터를 실행하세요. 이 예제에서 `sudo`는 운영 체제 패키지를 설치하는 용도로만 사용됩니다.

에뮬레이터는 중첩 가상화를 사용하므로 타이밍이 실제 Android 장치와 다를 수 있습니다. 에뮬레이터 벤치마크를 실제 장치 성능이 아닌 해당 CI 환경의 측정값으로 취급하세요.

## 동시성 제한 {#concurrency-limits}

각 계정에는 macOS와 Linux에 대해 독립적인 vCPU 및 메모리 동시성 제한이 있습니다. Tuist가 작업을 수용하기 전에 해당 플랫폼에서 현재 실행 중인 모든 작업과 비교하여 작업의 <.localized_link href="/guides/features/runners/profiles#machine-shapes">머신 셰이프</.localized_link>를 확인합니다. vCPU와 메모리가 모두 남은 용량 내에 맞을 때만 작업이 시작되며, 그렇지 않으면 용량이 available해질 때까지 큐에 대기합니다. 한 플랫폼에서의 작업은 다른 플랫폼의 용량을 소비하지 않습니다.

Runners 대시보드의 **동시성** 섹션은 시간별 최대 허용 vCPU 및 메모리 사용량을 보여줍니다. 빨간색 막대는 해당 시간 동안 사용량이 구성된 제한에 도달했음을 의미합니다. 제한을 초과하는 리소스를 필요로 하는 작업은 큐에 대기하므로 사용량은 선을 초과할 수 없습니다.

현재 제한은 각 차트 옆에 표시됩니다. 워크플로우가 정기적으로 제한에 도달하고 큐에서 시간을 보내는 경우, 계정 핸들, 플랫폼 및 예상 병렬 작업량을 포함하여 [저희에게 문의](mailto:contact@tuist.dev)하세요. 필요한 용량을 검토하고 제한을 높이는 데 도움을 드리겠습니다.

## 네트워크 액세스 {#network-access}

작업은 공용 인터넷으로 아웃바운드 연결을 열 수 있습니다. 사설 주소 범위(`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)는 차단되며, 러너는 인바운드 연결을 허용하지 않습니다.

| 플랫폼 | 아웃바운드 포트 |
| --- | --- |
| Linux | TCP 22(SSH), 80(HTTP) 및 443(HTTPS), plus DNS |
| macOS | 모든 포트 |

SSH는 `git@` 의존성, SSH 서브모듈, 배포 키 및 `ssh` 또는 `scp` 배포를 커버합니다. Linux 워크플로우에 다른 아웃바운드 포트가 필요한 경우 [저희에게 문의](mailto:contact@tuist.dev)하세요.

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub를 연결하고 runs-on을 Tuist 프로필로 지정하여 플릿에서 첫 번째 작업을 실행하세요."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="클러스터를 연결하고 Tuist 프로필 이름을 따서 큐를 명명한 후 단계에서 타겟팅하세요."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab을 한 번 연결하고 파이프라인 태그로 각 작업의 머신을 선택하세요."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="워크스페이스를 연결하고 자체 호스팅 러너 풀의 빌드를 Tuist 프로필에서 실행하세요."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="자신의 git 포지 또는 오케스트레이터에서 하나의 요청으로 작업을 실행하고 웹후크로 추적하세요."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="프로필"
    details="작업에서 참조하는 이름 지정된 머신 프로필로 플랫폼, 크기 및 Xcode 버전을 선택하세요."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="캐시 볼륨"
    details="Xcode, 모듈 및 Gradle 캐시와 기타 디렉토리를 작업 간에 유지하며, 각 실행마다 개인용 쓰기 가능 복사본을 제공합니다."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Once 그래프 액션 {#once-graph-actions}

계정에 원격 실행이 활성화되어 있고 서버가 호환되는 작업자 기능을 광고할 때, Once는 Tuist의 Linux 작업자에서 자격을 갖춘 그래프 명령 액션을 실행할 수 있습니다. 이는 위의 CI 제공업체 작업과 별개인 액션 수준의 실행입니다. 설정, 이미지 요구 사항 및 호환성 검사는 <.localized_link href="/guides/features/runners/once">Once 원격 실행</.localized_link>을 참조하세요.

## Tuist Runners를 사용하는 이유 {#why-tuist-runners}

대부분의 CI 러너 제공업체는 더 강력한 머신과 영구 캐시(일반적으로 CI 실행에 다시 마운트되는 공유 볼륨)를 제공하여 작업을 빠르게 만듭니다. 도움이 되지만 볼륨은 단순한 디스크일 뿐이며 이전 CI 실행이 남긴 모든 것을 담고 있습니다. 빌드가 실행되는 위치에 가장 최신 아티팩트만 가깝게 유지하도록 복제되지 않으며, 코드가 빌드되는 다른 장소에는 전혀 도달하지 못합니다.

빌드는 더 이상 한 곳에서 일어나지 않습니다. 동일한 코드는 개발자 노트북, CI 전반, 그리고 점점 더 많이 코딩 에이전트 및 기타 자동화 환경에서 컴파일됩니다. Tuist Runners는 사용하는 빌드 시스템에 관계없이 이러한 모든 환경이 이미 읽고 쓰는 동일한 <.localized_link href="/guides/features/cache">캐시</.localized_link>를 공유하기 때문에 다릅니다. 팀원이 노트북에서 웜업한 아티팩트, 에이전트가 생성한 아티팩트 또는 이전 빌드가 남겨둔 아티팩트는 러너에서 히트로 처리되며 그 반대도 마찬가지입니다. 별도로 웜업해야 하는 CI 캐시가 없으며 속도 향상도 CI에만 국한되지 않습니다.

여기에 더해 캐시는 러너와 동일한 사설 네트워크에 공동 배치되므로 캐시 읽기 및 쓰기가 공용 인터넷을 통과하는 대신 내부에 머물며 컴퓨팅 리소스와 가까이 유지됩니다.

종합하면 다음과 같습니다:

- **모든 환경에서 공유.** 러너는 개발자 머신, CI 및 코딩 에이전트와 동일한 캐시를 읽고 쓰므로 어디서든 수행된 작업이 모든 곳의 캐시를 웜업합니다.
- **컴퓨팅 리소스와 공동 배치.** 캐시 트래픽은 공용 인그레스를 통하지 않고 러너 옆의 내부 네트워크에 머무릅니다.
- **별도 추가가 아닌 단일 시스템.** 캐싱, <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>, <.localized_link href="/guides/features/test-sharding">테스트 샤딩</.localized_link> 및 <.localized_link href="/guides/features/build-insights">빌드 인사이트</.localized_link>가 모두 동일한 프로젝트와 계정을 대상으로 실행되므로 러너는 별도의 빌드 데이터 실로가 아닙니다.
