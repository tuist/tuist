---
{
  "title": "이미지",
  "titleTemplate": ":title · 러너 · 기능 · 가이드 · Tuist",
  "description": "Tuist 러너에 사전 설치된 내용: Xcode, 시뮬레이터 및 Metal 툴체인이 포함된 macOS 이미지와 Docker 및 Android SDK가 포함된 Ubuntu 이미지."
}
---
# 이미지 {#images}

모든 Tuist Runners 작업은 러너 이미지로 부팅된 새 가상 머신에서 시작됩니다. <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>이 이미지를 선택합니다: 플랫폼, macOS의 Xcode 버전, Linux의 Ubuntu 릴리스입니다. 작업이 끝나면 VM은 폐기되므로, 작업 중 설치한 모든 것은 다음 작업에서 사라집니다.

이미지는 워크플로우에 중요한 부분에서 GitHub 호스팅 러너를 따릅니다: 동일한 사용자, 홈 및 워크스페이스 경로, `ImageOS`, 비밀번호 없는 `sudo`, 그리고 대부분의 iOS, macOS 및 Linux 워크플로우가 기대하는 도구들입니다. 의도적으로 GitHub보다 작게 만들어졌으므로, 각 플랫폼별 차이점은 아래에 나열되어 있습니다.

## 이미지 선택하기 {#choosing-an-image}

- **Xcode, Apple SDK 또는 시뮬레이터:** 프로젝트가 빌드하는 Xcode 버전에 고정된 macOS 프로필.
- **Docker, Android 빌드 및 에뮬레이터, 또는 기타 Linux 도구:** Ubuntu 24.04의 Linux 프로필.
- **Ubuntu 24.04를 아직 지원하지 않는 의존성:** Ubuntu 22.04의 Linux 프로필.

macOS에서는 이미지가 아닌 Xcode를 선택합니다: 각 Xcode 버전은 자체 이미지이며, `26.4.1`에 고정된 프로필은 항상 Xcode 26.4.1으로 빌드된 이미지에서 실행됩니다. 두 개의 Xcode 버전을 실행하려면 각각에 대한 프로필을 생성하세요.

## macOS {#macos}

macOS 러너는 프로필의 **운영 체제**에 따라 **macOS 26 Tahoe** 또는 **macOS 27 Golden Gate**를 실행하는 Apple 실리콘(arm64) 가상 머신입니다. 선택 옵션이 존재하기 전에 생성된 프로필은 Tahoe에서 실행됩니다. 각 Xcode는 macOS 릴리스별로 별도로 빌드되므로, 프로필이 선택할 수 있는 Xcode 버전은 운영 체제에 따라 달라집니다. 러너 이름에는 정확한 macOS 버전이 포함되며, 예를 들어 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`와 같으며, 작업의 **작업 설정** 단계에 표시됩니다.

### Xcode {#xcode}

각 이미지에는 **정확히 하나의 Xcode**가 포함되어 있으며, `xcode-select`로 선택되므로 `xcodebuild` 및 `xcrun`는 설정 단계 없이 이를 사용합니다. 이는 여러 Xcode 버전을 제공하여 작업 시간에 전환할 수 있는 GitHub 호스팅 이미지와의 주요 차이점입니다. 사용 가능한 버전:

{{runner_macos_xcode_versions}}

- **경로.** Xcode는 `/Applications/Xcode_<version>.app`에 있습니다. 패치 구성 요소가 있는 버전의 경우, `/Applications/Xcode_<major>.<minor>.app`는 동일한 번들을 가리키므로 `Xcode_26.4.app`는 `Xcode_26.4.1.app`로 해결됩니다. GitHub 스타일의 경로를 하드코딩하거나 `xcode-select -s`를 호출하는 워크플로는 계속 작동합니다.
- **시뮬레이터.** 해당 Xcode와 함께 제공되는 iOS, tvOS, watchOS 및 visionOS 시뮬레이터 런타임은 이미지에 다운로드되므로, 첫 번째 `xcodebuild test`에서 이를 가져올 필요가 없습니다.
- **Metal 툴체인.** Xcode 26부터 Metal 컴파일러는 Xcode에 번들되지 않으며 별도로 다운로드해야 합니다. 모든 이미지에는 해당 Xcode에 맞는 Metal 툴체인이 포함되어 있으며, 작업이 실행되는 사용자에게 설치되므로 `xcrun metal` 및 `.metal` 소스가 있는 프로젝트는 `xcodebuild -downloadComponent MetalToolchain`를 실행하지 않고도 빌드됩니다.
- **베타.** 베타 프로필(예: `27.3-beta`)은 해당 릴리스의 최신 베타를 추적합니다. Apple이 새로운 베타를 출시하면 이미지가 재빌드되고 프로필은 사용자 측의 변경 없이 이를 따릅니다.

### 사전 설치된 소프트웨어 {#macos-software}

- **Apple 도구:** Xcode(이미지당 하나), 시뮬레이터 런타임, Metal 툴체인, `xcodes`, `xcbeautify`
- **Swift 및 iOS 도구:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **장치:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **언어 및 런타임:** Bundler와 함께 `rbenv`를 통한 Ruby(2.7 및 최신 3.x 릴리스 두 개, 가장 새로운 것이 기본값), npm, Yarn 및 pnpm과 함께 Node.js 24, Go, Java 21(Temurin, `JAVA_HOME`로 설정)
- **패키지 및 버전 관리자:** Homebrew, mise
- **버전 관리:** Git, Git LFS, Git Credential Manager, GitHub CLI(`gh`)
- **유틸리티:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI 에이전트:** GitHub Actions 러너, Buildkite 에이전트, Bitrise 에이전트 및 CLI, GitLab 작업 실행기
- **기타:** Rosetta 2, `safaridriver` 활성화됨

도구 버전은 이미지 빌드 시 Homebrew에서 가져오며, 이미지는 정기적으로 재빌드됩니다. 러너의 정확한 버전을 확인하려면 단계에서 출력하세요. 예를 들어 `swiftlint version` 또는 `xcodebuild -version`.

### 환경 {#macos-environment}

- **사용자 및 경로.** 작업은 `runner`로 실행되며, 홈은 `/Users/runner`, 워크스페이스는 `/Users/runner/work`로, GitHub 호스팅 러너와 동일한 경로이므로 이를 하드코딩하는 액션이 작동합니다.
- **`sudo`.** 비밀번호 없음. VM은 귀하의 작업 단독으로 소유됩니다.
- **Homebrew.** 접두사(`/opt/homebrew`)는 `runner`가 소유하므로 `brew install <formula>`는 `sudo` 없이 작동합니다. `HOMEBREW_NO_AUTO_UPDATE`가 설정되어 있습니다.
- **셸.** 단계는 로그인 셸에서 실행되므로 Homebrew, `rbenv` 및 Node.js는 `PATH`에 있습니다. `LANG`는 `en_US.UTF-8`입니다.
- **`ImageOS`** 는 GitHub 호스팅 러너와 마찬가지로 `macos26`이며, 이를 통해 사전 빌드된 바이너리를 선택하는 설정 액션용입니다.
- **인증서.** Apple의 WWDR(G3) 및 Developer ID(G2) 중간 인증서는 서명 및 공증용 시스템 신뢰 저장소에 있습니다.
- **개인정보 권한.** 두 가지 macOS 개인정보 승인은 GitHub 호스팅 이미지와 마찬가지로 사전에 부여됩니다: Apple Events를 통한 Finder 스크립팅(`create-dmg` 및 `osascript` 필요)과 UI 테스트에서 오디오를 녹음하는 앱이 필요한 iOS 시뮬레이터의 마이크 접근 권한입니다. `simctl privacy`와 같은 시뮬레이터 내부의 권한은 여전히 귀하의 작업 책임입니다.
- **디스크.** 각 작업은 최소 100GB의 무료 디스크 공간으로 시작됩니다.

### 포함되지 않음 {#macos-not-included}

- **Tuist CLI.** 프로젝트가 버전을 제어할 수 있도록 작업 중에 설치하세요. 예를 들어 mise를 사용하세요.
- **다른 Xcode 버전.** `xcode-select` 대신 Xcode 버전당 프로필을 사용하세요.
- **Docker.** macOS 러너에는 Docker 데몬이 없습니다. Linux 프로필을 사용하세요; <.localized_link href="/guides/features/runners/docker">Docker</.localized_link> 참조.
- **iOS 빌드가 거의 필요로 하지 않는 macOS용 GitHub 번들 툴체인**(예: 다른 Java 버전, Android SDK, .NET, Rust, Python 버전 또는 브라우저)은 Homebrew, mise 또는 설정 액션을 사용하여 단계에서 설치하세요.

## Linux {#linux}

Linux 러너는 프로필에 따라 선택된 **Ubuntu 24.04** 또는 **Ubuntu 22.04** 기반의 x86_64(amd64) 가상 머신입니다. 릴리스를 선택하는 방법은 <.localized_link href="/guides/features/runners/profiles#linux">프로필</.localized_link>을 참조하세요.

### 사전 설치된 소프트웨어 {#linux-software}

- **빌드 툴체인:** `build-essential`(GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **개발 헤더:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 with `pip` and `venv` (우분투 릴리스 버전)
- **컨테이너:** Buildx 및 Compose가 포함된 Docker CLI; 데몬은 작업과 함께 실행됩니다(<.localized_link href="/guides/features/runners/docker">Docker</.localized_link> 참조).
- **Kubernetes:** `kubectl`, Helm
- **Android:** `/usr/local/lib/android/sdk`에 있는 Android SDK에는 명령줄 도구, 플랫폼 도구 및 API 34 이상의 모든 플랫폼 및 빌드 도구 릴리스가 포함되며, 라이선스가 수락되어 있습니다.
- **버전 관리:** Git, Git LFS, OpenSSH 클라이언트, GitHub CLI(`gh`)
- **데이터베이스 클라이언트:** PostgreSQL, MariaDB, Redis(`redis-cli`), SQLite
- **아카이브:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **유틸리티:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI 에이전트:** GitHub Actions 러너, Buildkite 에이전트, Bitrise 에이전트 및 CLI, GitLab 작업 실행기

### 환경 {#linux-environment}

- **사용자 및 경로.** 작업은 UID 1000인 `runner`로 실행되며, 홈 디렉토리는 `/home/runner`이고, `docker` 그룹에 속하며, 비밀번호 없는 `sudo`를 사용합니다.
- **`ImageOS`** 는 GitHub 호스팅 러너와 일치하도록 `ubuntu24` 또는 `ubuntu22`입니다.
- **Android.** `ANDROID_HOME` 및 `ANDROID_SDK_ROOT`는 SDK를 가리킵니다. 에뮬레이터는 사전 설치되어 있지 않습니다. <.localized_link href="/guides/features/runners#android-emulators">Android 에뮬레이터</.localized_link>를 참조하세요.
- **로케일.** `LANG` 및 `LC_ALL`는 `C.UTF-8`이며, `DEBIAN_FRONTEND`는 `noninteractive`이므로 `sudo apt-get install`가 프롬프트를 표시하지 않습니다.

### 포함되지 않음 {#linux-not-included}

Linux 이미지는 GitHub가 사전 설치하는 모든 언어 툴체인 대신 빌드 기본 사항만 다룹니다. 일반적인 설정 액션(`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise 또는 `apt-get`를 사용하여 작업에 필요한 것을 설치하세요:

- **언어 런타임**(Java, Node.js, Go, Ruby, .NET 및 Rust 등).
- **Android NDK.** `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`를 사용하여 필요한 버전을 설치하세요. `ANDROID_NDK_HOME`는 설정되지 않은 상태로 유지되므로, 존재하지 않는 NDK를 가리키는 대신 빌드가 명확하게 실패합니다.
- **브라우저** 및 `kubectl`, Helm, `gh` 이외의 클라우드 CLI.

매번 설치하는 대신 작업 간에 툴체인을 유지하려면 <.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨</.localized_link>에 배치하세요.

## 이미지 업데이트 {#image-updates}

이미지는 Apple이 새로운 Xcode 또는 베타를 출시할 때, CI 에이전트가 업데이트될 때, 그리고 이미지 자체가 변경될 때 재빌드됩니다. 작업은 항상 완전하고 테스트된 이미지에서 실행됩니다. 새 이미지는 점진적으로 플릿에 배포되며 작업 실행 중에는 변경되지 않습니다.

워크플로우가 의존하는 도구가 누락된 경우 [문의하기](mailto:contact@tuist.dev) 또는 [커뮤니티 Slack](https://slack.tuist.dev)에서 질문하세요.
