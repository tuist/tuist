---
{
  "title": "執行器",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 執行器是專為 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 設計的受管 macOS 與 Linux 執行環境，其快取與運算資源並置，並與你的本機電腦共享。"
}
---
# 執行器 {#runners}

Tuist 執行器是專為你的 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 流程所管理的 macOS 與 Linux 執行器。與其將工作執行在 CI 供應商的主機上，你可以將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，讓它在 Tuist 的執行器群組中執行，並緊鄰團隊已使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝執行器代理程式，也無需維護基礎設施。若想在更換機器前了解影響 CI 費用的因素，請參閱[CI 費用](https://tuist.dev/solutions/ci-costs)。

採用它們通常只需對工作進行一行變更：

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

Linux 執行器預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你慣用的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle Managed Devices。存取裝置無需特殊的執行器設定檔、KVM 設定動作、權限變更或 `sudo`。

執行器映像包含 Android SDK。在啟動裝置前，請先安裝模擬器及其執行階段函式庫。若專案已定義名為 `pixel6` 的 Gradle Managed Device，GitHub Actions 工作會如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的 managed-device 任務。設定 **x86_64** 系統映像。選擇具備足夠記憶體以同時支援 Gradle 與模擬器的執行器規格；並行裝置會共享該工作的 CPU 與記憶體配置。

以一般執行器使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其計時可能與實體 Android 裝置不同。請將模擬器基準測試視為對該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳號針對 macOS 與 Linux 皆有獨立的 vCPU 與記憶體並行限制。在 Tuist 接受工作前，會檢查該工作的<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>是否符合該平台上目前所有執行中工作的容量。只有當工作的 vCPU 與記憶體皆符合剩餘容量時才會開始執行；否則會保持佇列狀態，直到容量可用為止。在一個平台上的工作絕不會消耗另一個平台的容量。

Air 帳號具有固定的並行限制。對於 Pro 與 Enterprise 帳號，Tuist 會根據經常性使用量以及近期無法與現行執行器並行的佇列工作，自動增加餘裕空間。自動調整僅會提高限制：既有的授權與合約最低容量將予以保留。成長幅度漸進且受安全上限約束，因此突發流量不會授予無限並行能力。較高的帳號限制並不保證能立即取得可用機器。

執行器儀表板的**並行**區段顯示每小時的最高核准 vCPU 與記憶體使用量，並以階梯線標示每小時開始時已知的限制。紅色長條表示達到該歷史閾值；這本身並不代表工作曾等待。小時內的增長可能使其峰值高於該時段起始線。目前限制會顯示於各圖表旁。在開始追蹤歷史記錄之前的期間沒有顯示限制線，而非假設的歷史數值。

若工作流程持續在安全上限處排隊，請[聯絡我們](mailto:contact@tuist.dev)並提供你的帳號代號、平台與預期平行工作量，以便我們檢視所需容量。

## 網路存取 {#network-access}

工作可以開啟通往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）已被封鎖，且執行器不接受任何入站連線。

| 平台 | 出站通訊埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 與 443 (HTTPS)，以及 DNS |
| macOS | 所有通訊埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。若 Linux 工作流程需要其他出站通訊埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在執行器群組上執行你的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中指向該佇列。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="一次性連接 GitLab，並透過管線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接你的工作區，並在 Tuist 設定檔上執行你自託管執行器集區的建置。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過單一請求從你自己的 git 平台或協調器執行工作，並透過 webhook 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="透過可從工作中參考的具名機器設定檔，選擇平台、大小與 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像"
    details="查看 macOS 與 Linux 執行器上預先安裝的內容：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取卷冊"
    details="在工作之間保留 Xcode、模組與 Gradle 快取以及任何其他目錄，並為每次執行提供私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo 圖形動作 {#struo-graph-actions}

<a id="once-graph-actions"></a>

當帳號啟用遠端執行且伺服器宣告相容的工作者能力時，Struo 可在 Tuist 的 Linux 工作者上執行符合條件的圖形命令動作。這是動作層級的執行，與上述 CI 供應商的工作分開。請參閱<.localized_link href="/guides/features/runners/struo">Struo 遠端執行</.localized_link>以了解設定、映像需求與相容性檢查。

## 為何選擇 Tuist 執行器 {#why-tuist-runners}

多數 CI 執行器供應商透過提供更強大的機器與持久化快取來加速工作，通常是將共享卷冊掛載回你的 CI 執行中。這確實有幫助，但卷冊只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會複製以確保只有最新的構件靠近建置執行處，也無法觸及程式碼在其他地方建置的環境。

建置不再只發生在單一地點。相同的程式碼會在開發者的筆記型電腦、CI 環境，以及愈來愈多的編碼代理與其他自動化環境中編譯。Tuist 執行器的不同之處在於，它們與所有這些環境共用同一個<.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用哪種建置系統，這些環境都會從該快取讀取並寫入。隊友在筆記型電腦上預熱的構件、代理產生的構件，或先前建置留下的構件，在執行器上都會命中快取，反之亦然。無需另外預熱獨立的 CI 快取，且加速效果不限於 CI。

此外，快取與執行器位於同一私有網路上，因此快取的讀寫流量保持在內部並靠近運算資源，而無需穿越公共網際網路。

綜合而言：

- **在所有環境間共享。** 執行器與你的開發機器、CI 及編碼代理讀寫相同的快取，因此在任何地方完成的工作都能為各處的快取預熱。
- **與運算資源共置。** 快取流量停留在執行器旁的內部網路，而非透過公共入口。
- **單一系統，非外加模組。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>與<.localized_link href="/guides/features/build-insights">建置洞察</.localized_link>皆針對同一專案與帳號執行，因此執行器並非獨立的建置資料孤島。
