---
{
  "title": "映像檔",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 預先安裝的內容：包含 Xcode、模擬器與 Metal 工具鏈的 macOS 映像檔，以及包含 Docker 與 Android SDK 的 Ubuntu 映像檔。"
}
---
# 映像檔 {#images}

每個 Tuist Runners 工作都會在從執行器映像檔啟動的全新虛擬機器中開始。你的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 會選擇映像檔：平台、macOS 上的 Xcode 版本，以及 Linux 上的 Ubuntu 發行版。工作結束時會捨棄該虛擬機器，因此工作中安裝的任何內容在下一次工作時都會消失。

這些映像檔遵循 GitHub 託管執行器中對工作流程至關重要的部分：相同的使用者、主目錄和工作區路徑、`ImageOS`、免密碼的 `sudo`，以及大多數 iOS、macOS 和 Linux 工作流程預期的工具。它們刻意比 GitHub 的更小，因此下方列出各平台的差異。

## 選擇映像檔 {#choosing-an-image}

- **Xcode、Apple SDK 或模擬器：** 使用鎖定至專案建置所用 Xcode 版本的 macOS 設定檔。
- **Docker、Android 建置與模擬器，或其他 Linux 工具：** 使用 Ubuntu 24.04 上的 Linux 設定檔。
- **尚不支援 Ubuntu 24.04 的相依性：** 使用 Ubuntu 22.04 上的 Linux 設定檔。

在 macOS 上，你選擇的是 Xcode，而非映像檔：每個 Xcode 版本都是獨立的映像檔，而鎖定至 `26.4.1` 的設定檔一律會在以 Xcode 26.4.1 建置的映像檔上執行。若要執行兩個 Xcode 版本，請為每個版本建立一個設定檔。

## macOS {#macos}

macOS 執行器是在 **macOS 26 Tahoe** 上執行的 Apple silicon (arm64) 虛擬機器。執行器名稱包含精確的 macOS 版本，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`，並出現在工作的 **設定工作** 步驟中。

### Xcode {#xcode}

每個映像檔包含**一個且僅一個 Xcode**，並由 `xcode-select` 選取，因此 `xcodebuild` 和 `xcrun` 可直接使用，無需額外設定步驟。這與 GitHub 託管映像檔的主要差異在於後者提供多個 Xcode 版本，供工作執行期間切換。可用版本：

{{runner_macos_xcode_versions}}

- **路徑。** Xcode 位於 `/Applications/Xcode_<version>.app`。對於含有修補程式元件的版本，`/Applications/Xcode_<major>.<minor>.app` 指向相同的套件，因此 `Xcode_26.4.app` 會解析為 `Xcode_26.4.1.app`。硬編碼 GitHub 風格路徑或使用 `xcode-select -s` 呼叫的工作流程仍可正常運作。
- **模擬器。** 隨附於該 Xcode 的 iOS、tvOS、watchOS 和 visionOS 模擬器執行階段已下載至映像檔中，因此首次執行 `xcodebuild test` 時無需擷取它們。
- **Metal 工具鏈。** 自 Xcode 26 起，Metal 編譯器不再與 Xcode 捆绑，必須單獨下載。每個映像檔都包含與其 Xcode 相符的 Metal 工具鏈，並安裝在工作執行的使用者帳戶下，因此 `xcrun metal` 以及包含 `.metal` 原始碼的專案無需執行 `xcodebuild -downloadComponent MetalToolchain` 即可建置。
- **Beta 版。** Beta 設定檔（例如 `27.3-beta`）會追蹤該發行版的最新 Beta 版。當 Apple 發布新的 Beta 版時，映像檔會重新建置，且設定檔會自動移至新版本，無需你進行任何變更。

### 預裝軟體 {#macos-software}

- **Apple 工具：** Xcode（每個映像檔一個）、模擬器執行階段、Metal 工具鏈、`xcodes`、`xcbeautify`
- **Swift 和 iOS 工具：** SwiftLint、SwiftFormat、SwiftGen、LicensePlist、Mint、Carthage、CocoaPods、fastlane
- **裝置：** `libimobiledevice`、`ideviceinstaller`、`ios-deploy`
- **語言和執行階段：** 透過 `rbenv` 提供的 Ruby（2.7 版及最新的兩個 3.x 版本，預設為最新版本）搭配 Bundler，Node.js 24 搭配 npm、Yarn 和 pnpm
- **套件和版本管理器：** Homebrew、mise
- **版本控制：** Git、Git LFS、Git Credential Manager、GitHub CLI (`gh`)
- **公用程式：** `jq`、`yq`、`curl`、`wget`、`zip`/`unzip`、CMake、GCC、AWS CLI
- **CI 代理程式：** GitHub Actions runner、Buildkite agent、Bitrise agent 與 CLI、GitLab job executor
- **其他：** Rosetta 2、已啟用 `safaridriver`

工具版本來自映像檔建置時的 Homebrew，且映像檔會定期重建。若要查看執行器上的精確版本，請在步驟中列印，例如 `swiftlint version` 或 `xcodebuild -version`。

### 環境 {#macos-environment}

- **使用者和路徑。** 工作以 `runner` 身分執行，主目錄為 `/Users/runner`，工作區為 `/Users/runner/work`，與 GitHub 託管執行器的路徑相同，因此硬編碼這些路徑的動作可以正常運作。
- **`sudo`。** 免密碼。該虛擬機器僅供你的工作使用。
- **Homebrew。** 前綴 (`/opt/homebrew`) 由 `runner` 擁有，因此 `brew install <formula>` 無需 `sudo` 即可運作。`HOMEBREW_NO_AUTO_UPDATE` 已設定。
- **Shell。** 步驟在登入 shell 中執行，因此 Homebrew、`rbenv` 和 Node.js 都在 `PATH` 中。`LANG` 為 `en_US.UTF-8`。
- **`ImageOS`** 為 `macos26`，與 GitHub 託管執行器相同，供依據此值選擇預建二進位檔的設定動作使用。
- **憑證。** Apple 的 WWDR (G3) 和 Developer ID (G2) 中繼憑證位於系統信任儲存區中，用於簽署和公證。
- **隱私權限。** 與 GitHub 託管映像檔一樣，預先授予兩項 macOS 隱私權限批准：透過 Apple Events 指令化 Finder（`create-dmg` 和 `osascript` 需要），以及 iOS 模擬器存取麥克風（在 UI 測試中錄音的應用程式需要）。模擬器內部的權限（例如 `simctl privacy`）仍由你的工作負責。
- **磁碟。** 每個工作開始時至少有 100 GB 的可用磁碟空間。

### 未包含 {#macos-not-included}

- **Tuist CLI。** 在工作中安裝它，例如使用 mise，以便由你的專案控制版本。
- **其他 Xcode 版本。** 為每個 Xcode 版本使用一個設定檔，而非使用 `xcode-select`。
- **Docker。** macOS 執行器沒有 Docker 守護程式。請使用 Linux 設定檔；參閱 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>。
- **GitHub 在 macOS 上捆綁的工具鏈**（iOS 建置較少需要），例如 Java、Android SDK、.NET、Rust、Python 版本或瀏覽器。請在步驟中使用 Homebrew、mise 或設定動作來安裝它們。

## Linux {#linux}

Linux 執行器是基於 **Ubuntu 24.04** 或 **Ubuntu 22.04** 的 x86_64 (amd64) 虛擬機器，由設定檔選擇。請參閱 <.localized_link href="/guides/features/runners/profiles#linux">設定檔</.localized_link> 以了解如何選擇發行版。

### 預裝軟體 {#linux-software}

- **建置工具鏈：** `build-essential`（GCC、G++、make）、autoconf、automake、libtool、`pkg-config`、CMake、Ninja、m4、bison、flex、gettext
- **開發標頭檔：** OpenSSL、libffi、zlib、bzip2、readline、SQLite、ncurses、libxml2、libxslt、libyaml、libcurl、uuid
- **Python：** Python 3 搭配 `pip` 和 `venv`（Ubuntu 發行版的版本）
- **容器：** 帶有 Buildx 和 Compose 的 Docker CLI；守護程式會與工作並行執行（參閱 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>）
- **Kubernetes：** `kubectl`、Helm
- **Android：** Android SDK 位於 `/usr/local/lib/android/sdk`，包含命令列工具、平台工具，以及從 API 34 開始的所有平台和建置工具版本，且已接受授權條款
- **版本控制：** Git、Git LFS、OpenSSH 用戶端、GitHub CLI (`gh`)
- **資料庫用戶端：** PostgreSQL、MariaDB、Redis (`redis-cli`)、SQLite
- **壓縮檔：** `tar`、`zip`/`unzip`、`xz`、`bzip2`、`p7zip`、`zstd`
- **公用程式：** `curl`、`wget`、`jq`、ripgrep、`fd`、`tree`、`less`、`vim`、HTTPie、`netcat`、`dig`、`ip`、`ping`、`file`
- **CI 代理程式：** GitHub Actions runner、Buildkite agent、Bitrise agent 與 CLI、GitLab job executor

### 環境 {#linux-environment}

- **使用者和路徑。** 工作以 `runner`（UID 1000）身分執行，主目錄為 `/home/runner`，屬於 `docker` 群組，並享有免密碼 `sudo`。
- **`ImageOS`** 為 `ubuntu24` 或 `ubuntu22`，與 GitHub 託管執行器相符。
- **Android。** `ANDROID_HOME` 和 `ANDROID_SDK_ROOT` 指向 SDK。模擬器未預裝；請參閱 <.localized_link href="/guides/features/runners#android-emulators">Android 模擬器</.localized_link>。
- **語系。** `LANG` 和 `LC_ALL` 為 `C.UTF-8`，且 `DEBIAN_FRONTEND` 為 `noninteractive`，因此 `sudo apt-get install` 不會提示。

### 未包含 {#linux-not-included}

Linux 映像檔涵蓋基本的建置需求，而非 GitHub 預裝的每種語言工具鏈。請使用常見的設定動作（`actions/setup-java`、`actions/setup-node`、`actions/setup-go`、`ruby/setup-ruby`）、mise 或 `apt-get` 來安裝工作所需的項目：

- **語言執行環境**，例如 Java、Node.js、Go、Ruby、.NET 和 Rust。
- **Android NDK。** 使用 `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` 安裝你需要的版本。`ANDROID_NDK_HOME` 保持未設定狀態，以便在建置失敗時明確指出問題，而非指向不存在的 NDK。
- **瀏覽器** 以及除 `kubectl`、Helm 和 `gh` 以外的雲端 CLI。

若要在不同工作之間保留工具鏈而非每次都安裝，請將其放在 <.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link> 上。

## 映像檔更新 {#image-updates}

當 Apple 發布新的 Xcode 或測試版、CI 代理程式更新，以及我們變更映像檔本身時，映像檔會重新建置。工作始終在完整且經過測試的映像檔上執行：新映像檔會逐漸部署到整個集群，且在工作執行期間絕不會變更。

如果你的工作流程依賴的工具遺失，請 [聯絡我們](mailto:contact@tuist.dev) 或在 [社群 Slack](https://slack.tuist.dev) 中詢問。
