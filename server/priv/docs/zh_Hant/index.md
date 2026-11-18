---
{
  "title": "什麼是 Tuist？",
  "description": "Tuist 是為工程團隊及其 AI 編碼代理打造的建置平台。它支援跨 Xcode、Gradle、Bazel、Elixir 和 Rust 的建置與測試工作流程；Once 支援目前處於 Canary 階段。功能因工具鏈而異，且 Rust 編譯快取仍屬實驗性功能。"
}
---

# 為團隊與程式碼代理打造的建置平台

**Tuist 是為工程團隊與其程式碼代理設計的建置平台。** 支援 Xcode、Gradle、Bazel、Elixir 與 Rust 的建置與測試工作流程；Once 支援目前處於 Canary 階段。它與你現有的建置系統協作，而非取代它們。可用功能取決於你的工具鏈：Rust 專案可取得 Cargo 建置與測試洞察，包含文件測試、不穩定測試偵測，以及實驗性編譯快取。Once 以原生方式連線，提供共享快取、建置與測試洞察、分片，以及受支援的應用程式預覽。

依照你的建置系統，選擇其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可直接連線，無需 Tuist CLI；其他路徑會說明需要安裝哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共享建置產出。支援 Xcode 編譯快取、Tuist 模組快取、Gradle 建置快取、Bazel 遠端快取、Elixir 相依性快取、Rust 實驗性編譯快取，以及 Once 共享動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="建置與測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 與 Once 專案的建置與測試耗時、失敗、不穩定性與回歸。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="在產生的 Xcode 專案中略過未變更的測試目標，並提供早期存取覆蓋策略，支援個別 XCTest/XCUITest 選擇。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管理的 macOS 與 Linux 執行器上執行 CI，靠近開發者機器使用的相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過網址分享受支援的行動應用程式、macOS 應用程式，以及 macOS/Linux 命令列工具。需符合建置、簽署與接收端相容性要求。"
    link="/guides/features/previews"
/>
  <.home_card
    title="產生的專案"
    details="以 Swift 描述 Xcode 專案並一致地產生它們。減少專案檔案衝突並啟用模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過註冊表協議取得受支援的 Swift 套件，而非複製其 Git 儲存庫。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="長期追蹤受支援的 Apple 與 Android 套件大小，並調查大小回歸。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體的團隊信賴

閱讀[客戶故事](https://tuist.dev/customers)，了解團隊採用的工作流程與回報的成果。
