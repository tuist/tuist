---
{
  "title": "映像檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 預先安裝的內容：包含 Xcode、模擬器與 Metal 工具鏈的 macOS 映像檔，以及包含 Docker 與 Android SDK 的 Ubuntu 映像檔。"
}
---
# 映像 {#images}

每個 Tuist Runners 工作都會在從執行器映像啟動的全新虛擬機器中開始。你的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 會選擇映像：平台、macOS 上的 Xcode 版本，以及 Linux 上的 Ubuntu 發行版。工作結束時會捨棄該虛擬機器，因此工作安裝的任何內容在下一次工作中都會消失。

這些映像在對工作流程重要的地方遵循 GitHub 託管執行器的設定：相同的使用者、家目錄與工作區路徑、`ImageOS`、免密碼的 `sudo`，以及大多數 iOS、macOS 和 Linux 工作流程預期會有的工具。它們刻意比 GitHub 的映像更小，因此下方列出各平台的差異。

## 選擇映像 {#choosing-an-image}

- **Xcode、Apple SDK 或模擬器：** 使用鎖定至專案建置所用 Xcode 版本的 macOS 設定檔。
- **Docker、Android 建置與模擬器，或其他 Linux 工具：** 使用 Ubuntu 24.04 上的 Linux 設定檔。
- **尚未支援 Ubuntu 24.04 的相依性：** 使用 Ubuntu 22.04 上的 Linux 設定檔。

在 macOS 上你選擇的是 Xcode，而非映像：每個 Xcode 版本都是獨立的映像，而鎖定至 `26.4.1` 的設定檔一律會在以 Xcode 26.4.1 建置的映像上執行。若要執行兩個 Xcode 版本，請為每個版本建立一個設定檔。

## macOS {#macos}

macOS 執行器是 Apple silicon（arm64）虛擬機器，執行 **macOS 26 Tahoe** 或 **macOS 27 Golden Gate**，取決於設定檔的 **作業系統** 名稱。在提供此選擇之前建立的設定檔會在 Tahoe 上執行。每個 Xcode 會針對每個 macOS 發行版分別建置，因此設定檔可選擇的 Xcode 版本取決於其作業系統。執行器名稱包含確切的 macOS 版本，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`，並出現在工作的 **設定工作** 步驟中。

### Xcode {#xcode}

每個映像檔包含**恰好一個 Xcode**，並透過 `xcode-select` 選取，因此 `xcodebuild` 和 `xcrun` 可直接使用，無需額外設定步驟。這與 GitHub 託管映像檔的主要差異在於後者提供多個 Xcode 版本，供工作在執行階段切換。可用版本：

{{runner_macos_xcode_versions}}

- **路徑。** Xcode 位於 `/Applications/Xcode_<version>.app`。對於含修補版本的版本，`/Applications/Xcode_<major>.<minor>.app` 指向同一個套件，因此 `Xcode_26.4.app` 會解析為 `Xcode_26.4.1.app`。將 GitHub 風格路徑寫死或使用 `xcode-select -s` 呼叫它的工作流程仍可正常運作。
- **模擬器。** 隨該 Xcode 提供的 iOS、tvOS、watchOS 與 visionOS 模擬器執行階段已下載至映像中，因此首次 `xcodebuild test` 無須再抓取它們。
- **Metal 工具鏈。** 自 Xcode 26 起，Metal 編譯器不再與 Xcode 捆綁，必須另行下載。每個映像都包含與其 Xcode 相符的 Metal 工具鏈，並安裝在工作執行的使用者帳戶下，因此 `xcrun metal` 以及包含 `.metal` 原始碼的專案無需執行 `xcodebuild -downloadComponent MetalToolchain` 即可建置。
- **Beta 版。** Beta 設定檔（例如 `27.3-beta`）會追蹤該發行版的最新 Beta 版。當 Apple 發布新的 Beta 版時，映像會重新建置，且設定檔會自動切換至新版本，無須你進行任何變更。

### 預先安裝的軟體 {#macos-software}

- **Apple 工具：** Xcode（每個映像一個）、模擬器執行階段、Metal 工具鏈、`xcodes`、`xcbeautify`
- **Swift 與 iOS 工具：** SwiftLint、SwiftFormat、SwiftGen、LicensePlist、Mint、Carthage、CocoaPods、fastlane
- **裝置：**`libimobiledevice`、`ideviceinstaller`、`ios-deploy`
- **語言與執行階段：** 透過 `rbenv` 提供的 Ruby（2.7 版與最新的兩個 3.x 發行版，以最新版為預設值）及 Bundler、Node.js 24 搭配 npm、Yarn 與 pnpm、Go、Java 21（Temurin，設為 `JAVA_HOME`）
- **套件與版本管理器：** Homebrew、mise
- **版本控制：** Git、Git LFS、Git Credential Manager、GitHub CLI（`gh`）
- **公用程式：**`jq`、`yq`、`curl`、`wget`、`zip`/`unzip`、CMake、GCC、AWS CLI
- **CI 代理程式：** GitHub Actions runner、Buildkite agent、Bitrise agent 與 CLI、GitLab job executor
- **其他：** Rosetta 2、已啟用 `safaridriver`

工具版本在建置映像時來自 Homebrew，且映像會定期重建。若要在執行器上查看確切版本，請在步驟中印出，例如 `swiftlint version` 或 `xcodebuild -version`。

### 環境 {#macos-environment}

- **使用者與路徑。** 工作以 `runner` 身分執行，家目錄為 `/Users/runner`，工作區為 `/Users/runner/work`，與 GitHub 託管執行器的路徑相同，因此將這些路徑寫死的動作仍可正常運作。
- **`sudo`。** 免密碼。該虛擬機器僅屬於你的工作。
- **Homebrew。** 前綴路徑（`/opt/homebrew`）由 `runner` 擁有，因此 `brew install <formula>` 無需 `sudo` 即可運作。`HOMEBREW_NO_AUTO_UPDATE` 已設定。
- **Shell。** 步驟在登入 shell 中執行，因此 Homebrew、`rbenv` 與 Node.js 都在 `PATH` 中。`LANG` 為 `en_US.UTF-8`。
- **`ImageOS`** 為 `macos26`，與 GitHub 託管執行器相同，供依據此值選擇預建二進位檔的設定動作使用。
- **憑證。** Apple 的 WWDR (G3) 與 Developer ID (G2) 中繼憑證位於系統信任存放區中，用於簽署與公證。
- **隱私權限。** 兩項 macOS 隱私權限已預先授予，與 GitHub 託管映像相同：透過 Apple Events 指令碼化 Finder（`create-dmg` 與 `osascript` 需要），以及 iOS 模擬器存取麥克風的權限（在 UI 測試中錄音的應用程式需要）。模擬器內部的權限（例如 `simctl privacy`）仍由你的工作負責。
- **磁碟。** 每個工作開始時至少有 100 GB 的可用磁碟空間。

### 未包含 {#macos-not-included}

- **Tuist CLI。** 請在工作中安裝（例如使用 mise），讓你的專案控制版本。
- **其他 Xcode 版本。** 請為每個 Xcode 版本使用獨立的設定檔，而非使用 `xcode-select`。
- **Docker。** macOS 執行器沒有 Docker daemon。請使用 Linux 設定檔；詳見 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>。
- **GitHub 在 macOS 上捆綁的工具鏈**（iOS 建置很少需要，例如其他 Java 版本、Android SDK、.NET、Rust、Python 版本或瀏覽器）。請在步驟中使用 Homebrew、mise 或設定動作來安裝。

## Linux {#linux}

Linux 執行器是基於 **Ubuntu 24.04** 或 **Ubuntu 22.04** 的 x86_64 (amd64) 虛擬機器，由設定檔選擇。請參閱 <.localized_link href="/guides/features/runners/profiles#linux">設定檔</.localized_link> 以了解如何選擇發行版。

### 預裝軟體 {#linux-software}

- **建置工具鏈：**`build-essential`（GCC、G++、make）、autoconf、automake、libtool、`pkg-config`、CMake、Ninja、m4、bison、flex、gettext
- **開發標頭檔：** OpenSSL、libffi、zlib、bzip2、readline、SQLite、ncurses、libxml2、libxslt、libyaml、libcurl、uuid
- **Python：** Python 3 附帶 `pip` 與 `venv`（版本取決於 Ubuntu 發行版）
- **容器：** Docker CLI 附帶 Buildx 與 Compose；daemon 會與工作並行執行（詳見 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>）
- **Kubernetes：**`kubectl`、Helm
- **Android：** Android SDK 位於 `/usr/local/lib/android/sdk`，包含命令列工具、platform-tools，以及從 API 34 起的所有 platform 與 build-tools 版本，且已接受授權條款
- **版本控制：** Git、Git LFS、OpenSSH client、GitHub CLI（`gh`）
- **資料庫用戶端：** PostgreSQL、MariaDB、Redis（`redis-cli`）、SQLite
- **壓縮檔：**`tar`、`zip`/`unzip`、`xz`、`bzip2`、`p7zip`、`zstd`
- **公用程式：**`curl`、`wget`、`jq`、ripgrep、`fd`、`tree`、`less`、`vim`、HTTPie、`netcat`、`dig`、`ip`、`ping`、`file`
- **CI 代理程式：** GitHub Actions runner、Buildkite agent、Bitrise agent 與 CLI、GitLab job executor

### 環境 {#linux-environment}

- **使用者與路徑。** 工作以 `runner`（UID 1000）身分執行，家目錄為 `/home/runner`，屬於 `docker` 群組，並享有免密碼 `sudo`。
- **`ImageOS`** 為 `ubuntu24` 或 `ubuntu22`，與 GitHub 託管執行器相符。
- **Android。**`ANDROID_HOME` 與 `ANDROID_SDK_ROOT` 指向 SDK。模擬器並未預裝；詳見 <.localized_link href="/guides/features/runners#android-emulators">Android 模擬器</.localized_link>。
- **地區設定。**`LANG` 與 `LC_ALL` 為 `C.UTF-8`，且 `DEBIAN_FRONTEND` 為 `noninteractive`，因此 `sudo apt-get install` 不會提示輸入。

### 未包含 {#linux-not-included}

Linux 映像涵蓋基本的建置需求，而非 GitHub 預裝的每種語言工具鏈。請使用常見的設定動作（`actions/setup-java`、`actions/setup-node`、`actions/setup-go`、`ruby/setup-ruby`）、mise 或 `apt-get` 來安裝工作所需的項目：

- **語言執行環境**，例如 Java、Node.js、Go、Ruby、.NET 與 Rust。
- **Android NDK。** 請使用 `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` 安裝你需要的版本。`ANDROID_NDK_HOME` 保持未設定狀態，以便在建置失敗時明確指出問題，而非指向不存在的 NDK。
- **瀏覽器**以及除 `kubectl`、Helm 與 `gh` 以外的雲端 CLI。

若要在不同工作之間保留工具鏈而非每次重新安裝，請將其放在 <.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link> 上。

## 映像更新 {#image-updates}

當 Apple 發布新的 Xcode 或測試版、CI 代理程式更新，或我們變更映像本身時，映像會重新建置。工作始終在完整且經過測試的映像上執行：新映像會逐步推送到執行器群組，且在工作執行期間絕不會變更。

如果你的工作流程依賴的工具遺失，請 [聯絡我們](mailto:contact@tuist.dev) 或在 [社群 Slack](https://slack.tuist.dev) 中詢問。
