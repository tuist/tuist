---
{
  "title": "Runners",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist Runners 係專為 GitHub Actions、Buildkite、GitLab CI 同 Bitrise 提供嘅受管 macOS 同 Linux 執行環境，具備與運算資源並置且可與你本地機器共享嘅快取。"
}
---
# Runners {#runners}

Tuist Runners 係專為你嘅 GitHub Actions、Buildkite、GitLab CI 同 Bitrise pipeline 而設嘅托管 macOS 同 Linux runner。唔使喺 CI 供應商提供嘅主機上執行 job，你只需要將 job 指向 Tuist <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>，佢就會喺 Tuist 嘅機群上運行，並與你團隊已經使用緊嘅同一個 <.localized_link href="/guides/features/cache">cache</.localized_link> 並排運作，無須安裝任何 runner agent，亦無須維護基礎設施。如果想了解喺更換機器之前乜嘢會影響你嘅 CI 賬單，請參閱 [CI costs](https://tuist.dev/solutions/ci-costs)。

採用通常只需要對 job 做一行更改：

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

## Linux 上嘅 Android 模擬器 {#android-emulators}

Linux runner 預設透過 `/dev/kvm` 提供硬件加速虛擬化。使用你平常嘅 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>（例如 `tuist-linux`）來運行 x86_64 Android 模擬器，包括 Gradle Managed Devices。訪問設備無須特別嘅 runner profile、KVM 設定動作、權限變更或 `sudo`。

Runner 映像包含 Android SDK。喺啟動設備之前，請安裝模擬器及其運行時庫。對於一個已經定義咗名為 `pixel6` 嘅 Gradle Managed Device 嘅項目，GitHub Actions job 會係咁樣：

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

使用你嘅 Android Gradle Plugin 所需嘅 Java 版本，並將測試任務替換為你項目中嘅 managed-device 任務。配置 **x86_64** 系統映像。選擇一個有足夠內存供 Gradle 同模擬器使用嘅 runner shape；並發設備會共享該 job 嘅 CPU 同內存分配。

以普通 runner 用戶身份運行模擬器。此示例中嘅 `sudo` 僅用於安裝操作系統軟件包。

模擬器使用嵌套虛擬化，因此其計時可能與實體 Android 設備不同。請將模擬器基準測試視為對該 CI 環境嘅測量，而非實體設備性能。

## 並發限制 {#concurrency-limits}

每個賬戶對於 macOS 同 Linux 都有獨立嘅 vCPU 同內存並發限制。喺 Tuist 接受 job 之前，它會檢查該 job 嘅 <.localized_link href="/guides/features/runners/profiles#machine-shapes">machine shape</.localized_link> 是否適合該平台上當前運行嘅所有 job。只有當其 vCPU 同內存都符合剩餘容量時，job 才會開始；否則它會保持排隊狀態，直到有可用容量。喺一個平台上嘅工作永遠不會消耗另一個平台嘅容量。

Air 賬戶有固定嘅並發限制：兩個標準 macOS job（16 vCPU / 48 GB）同 Linux 上嘅 16 vCPU / 64 GB。Pro 同 Enterprise 賬戶起始為六個標準 macOS job（48 vCPU / 144 GB）同 Linux 上嘅 64 vCPU / 128 GB，Tuist 會根據經常性使用情況同最近無法與活躍 runner 並排運行嘅排隊工作自動增加餘量。當限制較低時（最多十二個標準 macOS job，或 Linux 上嘅 128 vCPU / 512 GB），它可以每小時增長一次以容納所有排隊工作。超過此限制後，它每天最多增長一次，每次最多增長 50%，直至達到安全上限，因此突然嘅激增不會授予無限並發權限。自動調整只會增加限制：現有配額同合約規定嘅最低容量會被保留。較高嘅賬戶限制並不保證機器立即可用。

Runners 儀表板中嘅 **Concurrency** 部分顯示每小時峰值已接受嘅 vCPU 同內存使用量，並用階梯線表示每小時開始時已知嘅限制。紅色條形圖表示達到咗該歷史閾值；它們本身並不能證明 job 曾等待。一小時內嘅增加可能會使其峰值高於桶起始線。當前限制顯示喺每個圖表旁邊。歷史追蹤開始之前嘅時期沒有限制線，而不是假設嘅歷史值。

如果工作流繼續喺安全上限處排隊，請 [聯繫我哋](mailto:contact@tuist.dev) 並提供你嘅賬戶名稱、平台同預期嘅並行工作量，以便我哋審查所需容量。

## 網絡訪問 {#network-access}

Job 可以打開到公共互聯網嘅出站連接。私有地址範圍（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）被阻止，且 runner 不接受任何入站連接。

| 平台 | 出站端口 |
| --- | --- |
| Linux | TCP 22 (SSH)、80 (HTTP) 同 443 (HTTPS)，加上 DNS |
| macOS | 所有端口 |

SSH 涵蓋 `git@` 依賴項、SSH 子模塊、部署密鑰以及 `ssh` 或 `scp` 部署。如果 Linux 工作流需要其他出站端口，請 [聯繫我哋](mailto:contact@tuist.dev)。

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="連接 GitHub，將 runs-on 指向 Tuist profile，並喺機群上運行你嘅第一個 job。"
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="連接你嘅集群，以 Tuist profile 命名隊列，並從步驟中定位它。"
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="連接一次 GitLab，並使用 pipeline 標籤為每個 job 選擇機器。"
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="連接你嘅工作區，並喺 Tuist profiles 上運行你自託管 runner 池嘅構建。"
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="通過一個請求從你自己嘅 git forge 或編排器運行 job，並通過 webhooks 跟蹤它們。"
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiles"
    details="通過你從 job 中引用嘅命名機器 profile 來選擇平台、大小同 Xcode 版本。"
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Images"
    details="查看 macOS 同 Linux runner 上預裝咗乜嘢：Xcode、模擬器、Metal 工具鏈、Docker、Android SDK 等等。"
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Cache volumes"
    details="喺 job 之間保留 Xcode、模塊同 Gradle cache 以及任何其他目錄，每次運行都有專用嘅可寫副本。"
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo graph actions {#struo-graph-actions}

<a id="once-graph-actions"></a>

當賬戶啟用遠程執行且服務器宣傳兼容嘅 worker 能力時，Struo 可以喺 Tuist 嘅 Linux workers 上執行符合資格嘅 graph command actions。呢種係 action 級別嘅執行，同上面提到嘅 CI provider jobs 分開。請參閱 <.localized_link href="/guides/features/runners/struo">Struo remote execution</.localized_link> 以了解設置、鏡像要求同兼容性檢查。

## 點解選擇 Tuist Runners {#why-tuist-runners}

大多數 CI runner 提供商通過提供更強大嘅機器同持久 cache（通常係掛載返入你 CI 運行中嘅共享卷）來加快 job 速度。這確實有幫助，但卷只係一塊磁盤：它會保留之前 CI 運行留下嘅任何內容。它不會複製以保持最新構建產物靠近構建運行位置，亦無法覆蓋你代碼被構建嘅其他地方。

構建不再局限於單一地點。相同嘅代碼會喺開發者筆記本電腦、CI 環境，以及越來越多由編碼代理同其他自動化環境中編譯。Tuist Runners 之所以不同，係因為它們共享所有這些環境已經讀寫嘅同一個 <.localized_link href="/guides/features/cache">cache</.localized_link>，無論你使用乜嘢構建系統。隊友喺筆記本電腦上預熱嘅產物、代理生成嘅產物，或早期構建留下嘅產物，都會喺 runner 上命中 cache，反之亦然。無需單獨預熱 CI cache，而且速度提升並不限於 CI。

除此之外，cache 同 runner 位於同一私有網絡上，因此 cache 讀寫保持喺內部並靠近計算資源，而無需穿越公共互聯網。

總結如下：

- **跨所有環境共享。** Runner 讀寫嘅 cache 同你嘅開發者機器、CI 同編碼代理所用嘅相同，因此任何地方完成嘅工作都會為所有地方預熱 cache。
- **與計算資源共存。** Cache 流量停留喺 runner 旁邊嘅內部網絡上，而非經過公共入口。
- **單一系統，非附加組件。** Caching、<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/test-sharding">測試分片</.localized_link> 同 <.localized_link href="/guides/features/build-insights">構建洞察</.localized_link> 都針對同一項目同賬戶運行，因此 runner 並非獨立嘅構建數據孤島。
