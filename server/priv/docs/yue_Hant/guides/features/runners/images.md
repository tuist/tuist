---
{
  "title": "映像",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 預裝內容：包含 Xcode、模擬器同 Metal 工具鏈嘅 macOS 映像，以及包含 Docker 同 Android SDK 嘅 Ubuntu 映像。"
}
---
# 映像 {#images}

每個 Tuist Runners 工作都會在從執行器映像啟動的全新虛擬機器中開始。你的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 會選擇映像：包括平台、macOS 上的 Xcode 版本，以及 Linux 上的 Ubuntu 發行版。當工作結束時，虛擬機器會被捨棄，因此工作中安裝的任何內容在下一個工作中都會消失。

這些映像遵循 GitHub 託管執行器的慣例，這對於工作流程至關重要：相同的使用者、主目錄和工作區路徑、`ImageOS`、無需密碼的 `sudo`，以及大多數 iOS、macOS 和 Linux 工作流程所期望的工具。它們刻意比 GitHub 的更小，因此下文列出了每個平台的差異。

## 選擇映像 {#choosing-an-image}

- **Xcode、Apple SDK 或模擬器：** 使用鎖定至專案構建所用 Xcode 版本的 macOS 設定檔。
- **Docker、Android 構建和模擬器，或其他 Linux 工具：** 使用 Ubuntu 24.04 上的 Linux 設定檔。
- **尚未支援 Ubuntu 24.04 的依賴項：** 使用 Ubuntu 22.04 上的 Linux 設定檔。

在 macOS 上，你選擇的是 Xcode 而非映像：每個 Xcode 版本都有專屬的映像，而鎖定至 `26.4.1` 的設定檔始終會在基於 Xcode 26.4.1 構建的映像上運行。若要運行兩個 Xcode 版本，請為每個版本建立一個設定檔。

## macOS {#macos}

macOS 執行器是運行 **macOS 26 Tahoe** 或 **macOS 27 Golden Gate** 的 Apple silicon (arm64) 虛擬機器，具體取決於設定檔中 **作業系統** 的名稱。在提供此選擇之前建立的設定檔將在 Tahoe 上運行。每個 Xcode 都是針對每個 macOS 發行版單獨構建的，因此設定檔可選擇的 Xcode 版本取決於其作業系統。執行器的名稱包含確切的 macOS 版本，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`，並顯示在工作的 **設定工作** 步驟中。

### Xcode {#xcode}

每個映像包含 **恰好一個 Xcode**，透過 `xcode-select` 進行選擇，因此 `xcodebuild` 和 `xcrun` 無需設定步驟即可使用它。這是與 GitHub 託管映像的主要區別，後者提供多個 Xcode 版本以便在工作期間切換。可用版本：

{{runner_macos_xcode_versions}}

- **路徑。** Xcode 位於 `/Applications/Xcode_<version>.app`。對於包含修訂版本的版本，`/Applications/Xcode_<major>.<minor>.app` 指向同一個套件，因此 `Xcode_26.4.app` 會解析為 `Xcode_26.4.1.app`。硬編碼 GitHub 風格路徑或使用 `xcode-select -s` 呼叫它的工作流程仍可正常運作。
- **模擬器。** 隨該 Xcode 附帶的 iOS、tvOS、watchOS 和 visionOS 模擬器運行時已下載到映像中，因此首次 `xcodebuild test` 無須獲取它們。
- **Metal 工具鏈。** 自 Xcode 26 起，Metal 編譯器不再與 Xcode 捆綁，必須單獨下載。每個映像都包含與其 Xcode 匹配的 Metal 工具鏈，並安裝為工作運行的使用者，因此 `xcrun metal` 和包含 `.metal` 原始碼的專案無需運行 `xcodebuild -downloadComponent MetalToolchain` 即可構建。
- **Beta 版。** Beta 設定檔（例如 `27.3-beta`）會追蹤該發行版的最新 Beta 版。當 Apple 發布新的 Beta 版時，映像會重新構建，且設定檔會自動切換至新版本，無需你進行任何更改。

### 預裝軟體 {#macos-software}

- **Apple 工具：** Xcode（每個映像一個）、模擬器運行時、Metal 工具鏈、`xcodes`、`xcbeautify`
- **Swift 和 iOS 工具：** SwiftLint、SwiftFormat、SwiftGen、LicensePlist、Mint、Carthage、CocoaPods、fastlane
- **裝置：**`libimobiledevice`、`ideviceinstaller`、`ios-deploy`
- **語言和運行時：** 透過 `rbenv` 提供的 Ruby（2.7 及最新的兩個 3.x 版本，以最新版為預設值）搭配 Bundler、Node.js 24 搭配 npm、Yarn 和 pnpm、Go、Java 21（Temurin，設定為 `JAVA_HOME`）
- **套件和版本管理器：** Homebrew、mise
- **版本控制：** Git、Git LFS、Git Credential Manager、GitHub CLI (`gh`)
- **實用工具：**`jq`、`yq`、`curl`、`wget`、`zip`/`unzip`、CMake、GCC、AWS CLI
- **CI 代理：** GitHub Actions runner、Buildkite agent、Bitrise agent 和 CLI、GitLab job executor
- **其他：** Rosetta 2、已啟用 `safaridriver`

工具版本來自映像構建時的 Homebrew，且映像會定期重新構建。若要查看執行器上的確切版本，請在步驟中列印，例如 `swiftlint version` 或 `xcodebuild -version`。

### 環境 {#macos-environment}

- **使用者和路徑。** 工作以 `runner` 身份運行，主目錄為 `/Users/runner`，工作區為 `/Users/runner/work`，與 GitHub 託管執行器的路徑相同，因此硬編碼這些路徑的動作可以正常運作。
- **`sudo`。** 無需密碼。該虛擬機器專屬於你的工作。
- **Homebrew。** 前綴 (`/opt/homebrew`) 由 `runner` 擁有，因此 `brew install <formula>` 無需 `sudo` 即可運作。`HOMEBREW_NO_AUTO_UPDATE` 已設定。
- **Shell。** 步驟在登入 shell 中運行，因此 Homebrew、`rbenv` 和 Node.js 都在 `PATH` 中。`LANG` 為 `en_US.UTF-8`。
- **`ImageOS`** 為 `macos26`，與 GitHub 託管執行器一樣，供依據此選擇預構建二進位檔案的設定動作使用。
- **憑證。** Apple 的 WWDR (G3) 和 Developer ID (G2) 中繼憑證位於系統信任儲存區中，用於簽名和公證。
- **隱私權限。** 與 GitHub 託管映像一樣，預先授予兩項 macOS 隱私批准：透過 Apple Events 腳本化 Finder（`create-dmg` 和 `osascript` 需要），以及 iOS 模擬器存取麥克風（在 UI 測試中錄製音訊的應用程式需要）。模擬器內部的權限（例如 `simctl privacy`）仍由你的工作負責。
- **磁碟。** 每個工作開始時至少有 100 GB 的可用磁碟空間。

### 未包含 {#macos-not-included}

- **Tuist CLI。** 在工作中安裝它（例如使用 mise），以便你的專案控制版本。
- **其他 Xcode 版本。** 為每個 Xcode 版本使用一個設定檔，而不是使用 `xcode-select`。
- **Docker。** macOS 執行器沒有 Docker 守護程序。請使用 Linux 設定檔；參見 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>。
- **GitHub 在 macOS 上捆綁的工具鏈**（iOS 構建很少需要），例如其他 Java 版本、Android SDK、.NET、Rust、Python 版本或瀏覽器。請在步驟中使用 Homebrew、mise 或設定動作來安裝它們。

## Linux {#linux}

Linux 執行器是運行於 **Ubuntu 24.04** 或 **Ubuntu 22.04** 的 x86_64 (amd64) 虛擬機器，由設定檔選擇。參見 <.localized_link href="/guides/features/runners/profiles#linux">設定檔</.localized_link> 了解如何選擇發行版。

### 預裝軟體 {#linux-software}

- **構建工具鏈：**`build-essential`（GCC、G++、make）、autoconf、automake、libtool、`pkg-config`、CMake、Ninja、m4、bison、flex、gettext
- **開發標頭檔：** OpenSSL、libffi、zlib、bzip2、readline、SQLite、ncurses、libxml2、libxslt、libyaml、libcurl、uuid
- **Python：** Python 3 附帶 `pip` 和 `venv`（Ubuntu 發行版的版本）
- **容器：** Docker CLI 附帶 Buildx 和 Compose；守護程序與工作並行運行（參見 <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>）
- **Kubernetes：**`kubectl`、Helm
- **Android：** Android SDK 位於 `/usr/local/lib/android/sdk`，包含命令列工具、平台工具，以及從 API 34 起的所有平台和構建工具發行版，已接受授權
- **版本控制：** Git、Git LFS、OpenSSH 客戶端、GitHub CLI (`gh`)
- **資料庫客戶端：** PostgreSQL、MariaDB、Redis (`redis-cli`)、SQLite
- **壓縮歸檔：**`tar`、`zip`/`unzip`、`xz`、`bzip2`、`p7zip`、`zstd`
- **實用工具：**`curl`、`wget`、`jq`、ripgrep、`fd`、`tree`、`less`、`vim`、HTTPie、`netcat`、`dig`、`ip`、`ping`、`file`
- **CI 代理：** GitHub Actions runner、Buildkite agent、Bitrise agent 和 CLI、GitLab job executor

### 環境 {#linux-environment}

- **使用者和路徑。** 工作以 `runner`（UID 1000）身份運行，主目錄為 `/home/runner`，屬於 `docker` 群組，並擁有無需密碼的 `sudo`。
- **`ImageOS`** 為 `ubuntu24` 或 `ubuntu22`，與 GitHub 託管執行器一致。
- **Android。**`ANDROID_HOME` 和 `ANDROID_SDK_ROOT` 指向 SDK。模擬器未預裝；參見 <.localized_link href="/guides/features/runners#android-emulators">Android 模擬器</.localized_link>。
- **區域設定。**`LANG` 和 `LC_ALL` 為 `C.UTF-8`，且 `DEBIAN_FRONTEND` 為 `noninteractive`，因此 `sudo apt-get install` 不會提示輸入。

### 未包含 {#linux-not-included}

Linux 映像涵蓋構建基礎，而非 GitHub 預裝的每種語言工具鏈。使用常見的設定動作（`actions/setup-java`、`actions/setup-node`、`actions/setup-go`、`ruby/setup-ruby`）、mise 或 `apt-get` 安裝工作所需的內容：

- **語言運行時**，例如 Java、Node.js、Go、Ruby、.NET 和 Rust。
- **Android NDK。** 使用 `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` 安裝你需要的版本。`ANDROID_NDK_HOME` 保持未設定狀態，以便在沒有 NDK 時構建明確失敗，而不是指向一個不存在的 NDK。
- **瀏覽器**以及除 `kubectl`、Helm 和 `gh` 以外的雲端 CLI。

若要在工作之間保留工具鏈而無需每次安裝，請將其放在 <.localized_link href="/guides/features/runners/cache-volumes">快取卷</.localized_link> 上。

## 映像更新 {#image-updates}

當 Apple 發布新的 Xcode 或測試版、CI 代理更新，以及我們更改映像本身時，映像會重新構建。工作始終在完整且經過測試的映像上運行：新映像會逐步推送到集群，且在工作運行期間絕不會更改。

如果你的工作流程依賴的工具缺失，請 [聯絡我們](mailto:contact@tuist.dev) 或在 [社群 Slack](https://slack.tuist.dev) 中詢問。
