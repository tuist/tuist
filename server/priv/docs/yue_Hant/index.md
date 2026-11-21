---
{
  "title": "乜嘢係 Tuist？",
  "description": "Tuist 係一個為工程團隊同佢哋嘅編碼代理而設嘅建構平台。佢支援跨 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅建構同測試工作流程；Struo 支援處於 canary 階段。功能會因應工具鏈而異，而 Rust 編譯快取功能仍屬實驗性質。"
}
---

# 為團隊及其 AI 編碼代理而設的建置平台

**Tuist 是為工程團隊及其 AI 編碼代理而設的建置平台。** 它支援跨 Xcode、Gradle、Bazel、Elixir 和 Rust 的建置與測試工作流程；Struo 支援現處於 Canary 階段。它會配合你已使用的建置系統運作，而非取代它們。可用功能取決於你的工具鏈：Rust 專案可獲得 Cargo 建置與測試洞察，包括文件測試、不穩定測試偵測，以及實驗性編譯快取。Struo 以原生方式連接，提供共用快取、建置與測試洞察、分片，以及受支援的應用程式預覽。

請按照適合你建置系統的其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>操作。Struo 可直接連接，無需 Tuist CLI；其他路徑會說明需要安裝哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共用建置輸出。支援 Xcode 編譯快取、Tuist 模組快取、Gradle 建置快取、Bazel 遠端快取、Elixir 相依性快取、Rust 實驗性編譯快取，以及 Struo 共用動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/cache"
/>
  <.home_card
    title="建置與測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 及 Struo 專案的建置與測試耗時、失敗、不穩定性及回歸情況。"
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="在產生的 Xcode 專案中跳過未變更的測試目標，並提供早期存取覆蓋率策略，以進行個別 XCTest/XCUITest 選擇。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管 macOS 和 Linux 執行器上執行 CI，並使用與開發人員機器相同的快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過 URL 分享受支援的流動應用程式、macOS 應用程式，以及 macOS/Linux 命令列工具。需符合建置、簽署及接收者相容性要求。"
    link="/guides/features/previews"
/>
  <.home_card
    title="產生的專案"
    details="以 Swift 描述 Xcode 專案並一致地產生它們。減少專案檔案衝突並啟用模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過註冊表協定取得受支援的 Swift 套件，無須複製其 Git 儲存庫。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="隨時間追蹤受支援的 Apple 和 Android 套件大小，並調查大小回歸。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體的團隊信賴

閱讀[客戶故事](https://tuist.dev/customers)，了解團隊採用的工作流程及其報告的成果。
