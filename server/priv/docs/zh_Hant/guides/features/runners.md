---
{
  "title": "執行器",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 執行器是專為 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 設計的受管 macOS 與 Linux 執行環境，其快取與運算資源共置，並可與你的本機電腦共享。"
}
---
# 執行器 {#runners}

Tuist 執行器是為你的 GitHub Actions、Buildkite、GitLab CI 和 Bitrise 流程提供的受管 macOS 與 Linux 執行器。與其讓工作在 CI 供應商的託管機器上執行，你可以將工作指向 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，它就會在 Tuist 的機群中執行，並緊鄰團隊已在使用的相同<.localized_link href="/guides/features/cache">快取</.localized_link>，無需安裝執行器代理程式，也無需維護基礎設施。若想在更換機器前了解影響 CI 費用的因素，請參閱[CI 費用](https://tuist.dev/solutions/ci-costs)。

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

Linux 執行器預設透過 `/dev/kvm` 提供硬體加速虛擬化。使用你慣用的 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>（例如 `tuist-linux`）來執行 x86_64 Android 模擬器，包括 Gradle 受管裝置。存取裝置不需要特殊的執行器設定檔、KVM 設定動作、權限變更或 `sudo`。

執行器映像包含 Android SDK。在啟動裝置之前，請先安裝模擬器及其執行時期函式庫。對於已定義名為 `pixel6` 之 Gradle 受管裝置的專案，GitHub Actions 工作如下所示：

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

使用 Android Gradle Plugin 所需的 Java 版本，並將測試任務替換為專案的受管裝置任務。設定 **x86_64** 系統映像。選擇具備足夠記憶體以同時支援 Gradle 和模擬器的執行器規格；並行裝置會共用工作的 CPU 與記憶體配置。

以一般執行器使用者身分執行模擬器。此範例中的 `sudo` 僅用於安裝作業系統套件。

模擬器使用巢狀虛擬化，因此其耗時可能與實體 Android 裝置不同。請將模擬器基準測試視為該 CI 環境的測量結果，而非實體裝置效能。

## 並行限制 {#concurrency-limits}

每個帳戶針對 macOS 和 Linux 都有獨立的 vCPU 與記憶體並行限制。在 Tuist 接受工作之前，它會檢查該工作的<.localized_link href="/guides/features/runners/profiles#machine-shapes">機器規格</.localized_link>是否符合該平台上目前執行的所有工作。只有當工作的 vCPU 和記憶體都在剩餘容量範圍內時，工作才會開始執行；否則它會保持佇列狀態，直到有可用容量為止。在一個平台上的工作絕不會消耗另一個平台的容量。

Air 帳戶具有固定的並行限制：兩個標準 macOS 工作（16 vCPU / 48 GB）以及 Linux 上的 16 vCPU / 64 GB。Pro 和 Enterprise 帳戶從六個標準 macOS 工作（48 vCPU / 144 GB）以及 Linux 上的 64 vCPU / 128 GB 開始，Tuist 會根據經常性使用情況以及無法與活躍執行器並行的近期佇列工作，自動增加緩衝空間。當限制較低時（最多十二個標準 macOS 工作，或 Linux 上的 128 vCPU / 512 GB），它可以每小時最多增長一次以容納所有佇列工作。超過此限制後，它每天最多增長一次，每次最多增長 50%，直至達到安全上限，因此突然的爆發不會授予無限並行能力。自動調整只會增加限制：現有的授權和合約最低容量會保留。較高的帳戶限制並不保證機器立即可用。

執行器儀表板的**並行**區段顯示每小時峰值接受的 vCPU 和記憶體使用量，並以階梯線表示每小時開始時已知的限制。紅色長條代表達到該歷史閾值；它們本身並不能證明工作曾等待。一小時內的增加可能使其峰值高於桶起始線。當前限制顯示在每個圖表旁邊。在歷史追蹤開始之前的期間沒有限制線，而不是假設的歷史值。

如果工作流程持續在安全上限處佇列，請[聯絡我們](mailto:contact@tuist.dev)，提供你的帳戶代號、平台和預期平行工作量，以便我們檢視所需容量。

## 網路存取 {#network-access}

工作可以開啟通往公共網際網路的出站連線。私有位址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被封鎖，且執行器不接受任何入站連線。

| 平台 | 出站連接埠 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 和 443 (HTTPS)，以及 DNS |
| macOS | 所有連接埠 |

SSH 涵蓋 `git@` 相依性、SSH 子模組、部署金鑰，以及 `ssh` 或 `scp` 部署。如果 Linux 工作流程需要其他出站連接埠，請[聯絡我們](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist 設定檔，並在機群上執行你的第一個工作。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中指向它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接 GitLab 一次，並使用流水線標籤選擇每個工作的機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接你的工作區，並在 Tuist 設定檔上執行你自託管執行器池的建置。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="透過單一請求從你自己的 git 鍛造廠或協調器執行工作，並使用 webhook 追蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="設定檔"
    details="選擇平台、大小和 Xcode 版本，使用你在工作中參考的具名機器設定檔。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="映像"
    details="查看 macOS 和 Linux 執行器上預裝的內容：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="快取卷冊"
    details="在工作之間保留 Xcode、模組和 Gradle 快取以及任何其他目錄，每次執行都有私有的可寫入副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo 圖表動作 {#struo-graph-actions}

<a id="once-graph-actions"></a>

當帳戶啟用遠端執行且伺服器宣告相容的工作者能力時，Struo 可以在 Tuist 的 Linux 工作者上執行符合條件的圖表命令動作。這是動作層級的執行，與上述 CI 提供者工作分開。請參閱 <.localized_link href="/guides/features/runners/struo">Struo 遠端執行</.localized_link> 以了解設定、映像需求及相容性檢查。

## 為何選擇 Tuist 執行器 {#why-tuist-runners}

大多數 CI 執行器提供者透過提供更強大的機器和持久化快取（通常是掛載回 CI 執行的共用磁碟區）來加速工作。這確實有幫助，但磁碟區只是磁碟：它會保留先前 CI 執行所留下的任何內容。它不會為了將最新的構件保持在建置執行位置附近而進行複寫，也無法觸及程式碼在其他地方建置的環境。

建置不再只發生在單一地點。相同的程式碼會在開發者的筆記型電腦、CI 環境，以及越來越多的編碼代理和其他自動化環境中編譯。Tuist 執行器的不同之處在於，它們共用所有這些環境已經讀寫的同一個 <.localized_link href="/guides/features/cache">快取</.localized_link>，無論你使用何種建置系統。隊友在筆記型電腦上預熱的構件、代理產生的構件，或先前建置留下的構件，都能在執行器上命中快取，反之亦然。無需單獨預熱 CI 快取，且速度提升不僅限於 CI。

此外，快取與執行器位於同一個私有網路上，因此快取的讀寫流量保持在內部並靠近運算資源，而不必跨越公共網際網路。

綜合起來：

- **在所有環境中共用。** 執行器與你的開發者機器、CI 和編碼代理讀寫相同的快取，因此在任何地方完成的工作都能為各處的快取預熱。
- **與運算資源共置。** 快取流量停留在執行器旁的內部網路上，而非透過公共入口。
- **單一系統，非外掛附加。** 快取、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link>和<.localized_link href="/guides/features/build-insights">建置洞察</.localized_link>都針對相同的專案和帳戶執行，因此執行器並非獨立的建置資料孤島。
