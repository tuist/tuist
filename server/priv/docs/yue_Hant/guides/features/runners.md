---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 提供嘅托管 macOS 同 Linux 執行環境，具備與計算資源共置並與你本地機器共享嘅快取。"
}
---
# Runners {#runners}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前處於僅限邀請階段，以便我們擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯絡我們，以請求存取你的帳戶。當 Runners 全面開放時，我們將公佈定價。


Tuist Runners 是專為你的 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 流程提供的受管 macOS 和 Linux Runner。與其在你 CI 提供商的託管機器上執行作業，不如將作業指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，它就會在 Tuist 的機隊上執行，緊鄰你團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝 Runner 代理程式，也無需維護基礎設施。若要了解在更換機器前什麼因素影響你的 CI 帳單，請參閱[CI 成本](https://tuist.dev/solutions/ci-costs)。

採用它們通常只需對作業進行一行更改：

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

## Linux 上的 Android 模擬器 {#android-emulators}

Linux Runner 預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你普通的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。無需特殊的 Runner 設定檔、KVM 設定動作、權限變更或 `sudo` 即可存取裝置。

Runner 映像包含 Android SDK。在啟動裝置之前，請安裝模擬器及其執行時期函式庫。對於已定義名為 `pixel6` 的 Gradle Managed Device 的專案，GitHub Actions 作業如下所示：

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

使用你的 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像。選擇具有足夠記憶體供 Gradle 和模擬器使用的 Runner 規格；並行裝置會共用作業的 CPU 和記憶體配置。

以一般 Runner 使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其計時可能與實體 Android 裝置不同。將模擬器基準測試視為該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶都有獨立的 macOS 和 Linux vCPU 及記憶體並行限制。在 Tuist 接受作業之前，它會檢查作業的 <.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link> 與目前在該平台上執行的所有作業。只有當作業的 vCPU 和記憶體都符合剩餘容量時，作業才會開始；否則它會保持佇列狀態，直到容量可用為止。在一個平台上的工作永遠不會消耗另一個平台的容量。

Runners 儀表板的 **並行** 部分顯示每小時的最高允許 vCPU 和記憶體使用量。紅條表示使用量在該小時內的某個時間點達到了設定的限制。使用量不能超過該線，因為會使任一資源超過其限制的作業仍會保持在佇列中。

你的當前限制顯示在每個圖表旁邊。如果你的工作流程經常達到這些限制並在佇列中花費時間，請[聯絡我們](mailto:contact@tuist.dev)，提供你的帳戶代號、平台和預期並行工作量。我們將檢視所需容量並協助提高限制。

## 網路存取 {#network-access}

作業可以開啟連接到公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被封鎖，且 Runner 不接受任何入站連線。

| 平台 | 出站連接埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有連接埠 |

SSH 涵蓋 `git@` 依賴項、SSH 子模組、部署金鑰以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站連接埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機隊上執行你的第一個作業。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接 GitLab 一次，並使用流水線標籤選擇每個作業的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接你的工作區，並在 Tuist 設定檔上執行你自託管 Runner 池的建置。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過一個請求從你自己的 git forge 或協調器執行作業，並透過 webhook 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="使用你從作業中參考的具名機器設定檔，選擇平台、大小和 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="快取卷冊"
    details="在作業之間保留 Xcode、模組和 Gradle 快取以及任何其他目錄，每次執行都有私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Once 圖形動作 {#once-graph-actions}

當帳戶啟用遠端執行功能，且伺服器宣告相容的 Worker 能力時，Once 可以在 Tuist 的 Linux Worker 上執行符合資格的圖形指令動作。這是動作層級的執行，與上述 CI 供應商的作業分開。請參閱 <.localized_link href="/guides/features/runners/once">Once 遠端執行</.localized_link> 以了解設定、映像檔需求和相容性檢查。

## 為何選擇 Tuist Runners {#why-tuist-runners}

大多數 CI Runner 供應商透過提供更強大的機器和持久化快取來加速作業，通常是將共享卷冊掛載回你的 CI 執行環境中。這確實有幫助，但卷冊只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會進行複寫以確保只有最新的構件靠近建置執行位置，也無法涵蓋程式碼在其他地方建置的情況。

建置不再只發生在單一位置。相同的程式碼會在開發者的筆記型電腦、CI 環境，以及愈來愈多的編碼代理程式和其他自動化環境中編譯。Tuist Runners 的不同之處在於，它們共享所有這些環境已經讀取和寫入的同一個 <.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統。隊友在筆記型電腦上預熱的構件、代理程式產生的構件，或先前建置留下的構件，都會在 Runner 上命中，反之亦然。不需要單獨預熱 CI 快取，且加速效果不限於 CI。

此外，快取與 Runner 位於同一個私有網路上共置，因此快取的讀寫保持在內部並靠近運算資源，而無需跨越公共網際網路。

綜合起來：

- **在所有環境中共享。** Runner 讀取和寫入的快取與你的開發者機器、CI 和編碼代理程式相同，因此在任何地方完成的工作都會預熱各處的快取。
- **與運算資源共置。** 快取流量保持在 Runner 旁邊的內部網路上，而非透過公共入口。
- **單一系統，非外掛式。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>和<.localized_link href="/guides/features/build-insights">建置洞察</.localized_link>都針對同一個專案和帳戶執行，因此 Runner 不是獨立的建置數據孤島。
