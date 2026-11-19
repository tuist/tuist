---
{
  "title": "乜嘢係 Tuist？",
  "description": "Tuist 係一個為工程團隊同佢哋嘅編碼代理而設嘅構建平台。佢支援跨 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅構建同測試工作流程；Once 支援仲處於 Canary 階段。功能會因工具鏈而異，而 Rust 編譯快取功能仍屬實驗性質。"
}
---

# 為團隊及其編碼代理而設的構建平台

**Tuist 是為工程團隊及其編碼代理而設的構建平台。** 它支援 Xcode、Gradle、Bazel、Elixir 和 Rust 的構建與測試工作流程；Once 支援目前處於 canary 階段。它會配合你現已使用的構建系統，而非取代它們。可用功能取決於你的工具鏈：Rust 專案可取得 Cargo 構建與測試洞察，包括 doctests、不穩定測試偵測，以及實驗性編譯快取。Once 以原生方式連接，提供共享快取、構建與測試洞察、分片，以及受支援的應用程式預覽。

依照你的構建系統，選擇其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可直接連接，無需 Tuist CLI；其他路徑則說明需要安裝哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共享構建產出。支援 Xcode 的編譯快取、Tuist 的模組快取、Gradle 的構建快取、Bazel 的遠端快取、Elixir 的依賴快取、Rust 的實驗性編譯快取，以及 Once 的共享動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="構建與測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 專案的構建與測試耗時、失敗、不穩定性及回退。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="在生成的 Xcode 專案中跳過未變更的測試目標，並提供早期存取覆蓋策略，以便對個別 XCTest/XCUITest 進行選擇。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管的 macOS 與 Linux 執行器上執行 CI，這些執行器靠近開發者機器所使用的相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過 URL 分享受支援的流動應用程式、macOS 應用程式，以及 macOS/Linux 命令列工具。須符合構建、簽署及接收端相容性要求。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成的專案"
    details="以 Swift 描述 Xcode 專案並一致地生成它們。減少專案檔案衝突，並解鎖模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過註冊表協議取得受支援的 Swift 套件，無須克隆其 Git 儲存庫。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="隨時間追蹤受支援的 Apple 與 Android 套件大小，並調查大小回退。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體的團隊信賴

閱讀[客戶故事](https://tuist.dev/customers)，了解團隊採用的工作流程及其回報的成果。
