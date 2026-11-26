---
{
  "title": "Images",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "What's preinstalled on Tuist Runners: the macOS images with Xcode, simulators and the Metal toolchain, and the Ubuntu images with Docker and the Android SDK."
}
---
# Images {#images}

Every Tuist Runners job starts in a fresh virtual machine booted from a runner image. Your <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> chooses the image: the platform, the Xcode version on macOS, and the Ubuntu release on Linux. The VM is discarded when the job ends, so anything a job installs is gone for the next one.

The images follow GitHub-hosted runners where it matters to workflows: the same user, home and workspace paths, `ImageOS`, passwordless `sudo`, and the tools most iOS, macOS and Linux workflows expect. They're intentionally smaller than GitHub's, so the differences are listed for each platform below.

## Choosing an image {#choosing-an-image}

- **Xcode, Apple SDKs or simulators:** a macOS profile pinned to the Xcode version your project builds with.
- **Docker, Android builds and emulators, or other Linux tooling:** a Linux profile on Ubuntu 24.04.
- **A dependency that doesn't support Ubuntu 24.04 yet:** a Linux profile on Ubuntu 22.04.

On macOS you pick the Xcode, not the image: each Xcode version is its own image, and a profile pinned to `26.4.1` always runs on the image built with Xcode 26.4.1. To run two Xcode versions, create a profile for each.

## macOS {#macos}

macOS runners are Apple silicon (arm64) virtual machines running **macOS 26 Tahoe** or **macOS 27 Golden Gate**, whichever the profile's **Operating system** names. Profiles created before the choice existed run on Tahoe. Each Xcode is built separately for each macOS release, so the Xcode versions a profile can pick depend on its operating system. A runner's name includes the exact macOS version, for example `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, and appears in the job's **Set up job** step.

### Xcode {#xcode}

Each image contains **exactly one Xcode**, which is selected with `xcode-select`, so `xcodebuild` and `xcrun` use it without a setup step. This is the main difference from GitHub-hosted images, which ship several Xcode versions to switch between at job time. Available versions:

{{runner_macos_xcode_versions}}

- **Path.** Xcode is at `/Applications/Xcode_<version>.app`. For a version with a patch component, `/Applications/Xcode_<major>.<minor>.app` points at the same bundle, so `Xcode_26.4.app` resolves to `Xcode_26.4.1.app`. Workflows that hardcode a GitHub-style path or call `xcode-select -s` with it keep working.
- **Simulators.** The iOS, tvOS, watchOS and visionOS simulator runtimes that ship with that Xcode are downloaded into the image, so the first `xcodebuild test` doesn't have to fetch them.
- **Metal toolchain.** Since Xcode 26, the Metal compiler isn't bundled with Xcode and has to be downloaded separately. Every image includes the Metal toolchain matching its Xcode, installed for the user jobs run as, so `xcrun metal` and projects with `.metal` sources build without running `xcodebuild -downloadComponent MetalToolchain`.
- **Betas.** Beta profiles (for example `27.3-beta`) track the latest beta of that release. When Apple ships a new beta, the image is rebuilt and the profile moves to it without a change on your side.

### Preinstalled software {#macos-software}

- **Apple tooling:** Xcode (one per image), simulator runtimes, Metal toolchain, `xcodes`, `xcbeautify`
- **Swift and iOS tooling:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Devices:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Languages and runtimes:** Ruby through `rbenv` (2.7 and the two latest 3.x releases, the newest as default) with Bundler, Node.js 24 with npm, Yarn and pnpm, Go, Java 21 (Temurin, set as `JAVA_HOME`)
- **Package and version managers:** Homebrew, mise
- **Version control:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Utilities:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI agents:** GitHub Actions runner, Buildkite agent, Bitrise agent and CLI, GitLab job executor
- **Other:** Rosetta 2, `safaridriver` enabled

Tool versions come from Homebrew when the image is built, and images are rebuilt regularly. To see the exact version on a runner, print it in a step, for example `swiftlint version` or `xcodebuild -version`.

### Environment {#macos-environment}

- **User and paths.** Jobs run as `runner`, with home `/Users/runner` and workspace `/Users/runner/work`, the same paths as GitHub-hosted runners, so actions that hardcode them work.
- **`sudo`.** Passwordless. The VM belongs to your job alone.
- **Homebrew.** The prefix (`/opt/homebrew`) is owned by `runner`, so `brew install <formula>` works without `sudo`. `HOMEBREW_NO_AUTO_UPDATE` is set.
- **Shell.** Steps run in a login shell, so Homebrew, `rbenv` and Node.js are on `PATH`. `LANG` is `en_US.UTF-8`.
- **`ImageOS`** is `macos26`, as on GitHub-hosted runners, for setup actions that pick prebuilt binaries by it.
- **Certificates.** Apple's WWDR (G3) and Developer ID (G2) intermediate certificates are in the system trust store for signing and notarization.
- **Privacy permissions.** Two macOS privacy approvals are granted in advance, as on GitHub-hosted images: scripting Finder through Apple Events, which `create-dmg` and `osascript` need, and the iOS Simulator's access to the microphone, which apps recording audio in UI tests need. Permissions inside a simulator, such as `simctl privacy`, remain your job's responsibility.
- **Disk.** Each job starts with at least 100 GB of free disk space.

### Not included {#macos-not-included}

- **The Tuist CLI.** Install it in the job, for example with mise, so your project controls the version.
- **Other Xcode versions.** Use a profile per Xcode version instead of `xcode-select`.
- **Docker.** macOS runners have no Docker daemon. Use a Linux profile; see <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **Toolchains GitHub bundles on macOS** that iOS builds rarely need, such as other Java versions, the Android SDK, .NET, Rust, Python versions or browsers. Install them in a step with Homebrew, mise or a setup action.

## Linux {#linux}

Linux runners are x86_64 (amd64) virtual machines on **Ubuntu 24.04** or **Ubuntu 22.04**, chosen by the profile. See <.localized_link href="/guides/features/runners/profiles#linux">Profiles</.localized_link> for how to pick a release.

### Preinstalled software {#linux-software}

- **Build toolchain:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Development headers:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 with `pip` and `venv` (the Ubuntu release's version)
- **Containers:** Docker CLI with Buildx and Compose; the daemon runs alongside the job (see <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK at `/usr/local/lib/android/sdk` with command-line tools, platform-tools, and every platform and build-tools release from API 34 up, licenses accepted
- **Version control:** Git, Git LFS, OpenSSH client, GitHub CLI (`gh`)
- **Database clients:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Archives:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Utilities:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI agents:** GitHub Actions runner, Buildkite agent, Bitrise agent and CLI, GitLab job executor

### Environment {#linux-environment}

- **User and paths.** Jobs run as `runner` (UID 1000) with home `/home/runner`, in the `docker` group, with passwordless `sudo`.
- **`ImageOS`** is `ubuntu24` or `ubuntu22`, matching GitHub-hosted runners.
- **Android.** `ANDROID_HOME` and `ANDROID_SDK_ROOT` point at the SDK. The emulator isn't preinstalled; see <.localized_link href="/guides/features/runners#android-emulators">Android emulators</.localized_link>.
- **Locale.** `LANG` and `LC_ALL` are `C.UTF-8`, and `DEBIAN_FRONTEND` is `noninteractive`, so `sudo apt-get install` doesn't prompt.

### Not included {#linux-not-included}

The Linux image covers the build basics rather than every language toolchain GitHub preinstalls. Install what your job needs with the usual setup actions (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), with mise, or with `apt-get`:

- **Language runtimes** such as Java, Node.js, Go, Ruby, .NET and Rust.
- **The Android NDK.** Install the version you need with `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`. `ANDROID_NDK_HOME` is left unset so that a build fails clearly instead of pointing at an NDK that isn't there.
- **Browsers** and cloud CLIs other than `kubectl`, Helm and `gh`.

To keep a toolchain between jobs instead of installing it every time, put it on a <.localized_link href="/guides/features/runners/cache-volumes">cache volume</.localized_link>.

## Image updates {#image-updates}

Images are rebuilt when Apple ships a new Xcode or beta, when the CI agents are updated, and when we change the images themselves. A job always runs on a complete, tested image: new images roll out to the fleet gradually and never change while a job runs.

If a tool your workflow relies on is missing, [contact us](mailto:contact@tuist.dev) or ask in the [community Slack](https://slack.tuist.dev).
