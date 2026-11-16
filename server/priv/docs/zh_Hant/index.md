---
{
  "title": "什麼是 Tuist？",
  "description": "Tuist 是為工程團隊及其 AI 編碼代理打造的建置平台。它支援 Xcode、Gradle、Bazel、Elixir 和 Rust 的建置與測試工作流程；Once 支援目前處於 Canary 階段。功能因工具鏈而異，且 Rust 編譯快取仍屬實驗性功能。"
}
---

# 為團隊與其編碼代理打造的建置平台

**Tuist 是為工程團隊與其編碼代理打造的建置平台。** 它支援跨 Xcode、Gradle、Bazel、Elixir 與 Rust 的建置與測試工作流程；Once 的支援目前處於 Canary 階段。它與你現有的建置系統協作，而非取代它們。可用功能取決於你的工具鏈：Rust 專案可取得 Cargo 建置與測試洞察，包含文件測試、不穩定測試偵測，以及實驗性編譯快取。Once 可原生連接，以共用快取、建置與測試洞察、分片，以及支援的應用程式預覽。

依照你的建置系統，選擇其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可直接連接，無需 Tuist CLI；其他路徑會說明需要安裝哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共用建置產出。支援 Xcode 的編譯快取、Tuist 的模組快取、Gradle 的建置快取、Bazel 的遠端快取、Elixir 的相依性快取、Rust 的實驗性編譯快取，以及 Once 的共用動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="建置與測試洞察"
    details="追蹤跨 Xcode、Gradle、Bazel、Elixir、Rust 與 Once 專案的建置與測試耗時、失敗、不穩定性與回歸。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="僅執行受變更影響的測試（適用於產生的 Xcode 專案），讓回饋在數秒內到位。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管的 macOS 與 Linux 執行器上執行 CI，並贴近開發者機器使用的相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過網址立即分享你的應用程式。無需等待商店審核，也無需複雜設定。"
    link="/guides/features/previews"
/>
  <.home_card
    title="產生的專案"
    details="以 Swift 描述 Xcode 專案並一致地產生它們。消除合併衝突並啟用模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過由 Tuist 快取網路支援的註冊表，在數秒內解析 Swift 套件，而非數分鐘。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="分析並保持應用程式精簡，讓使用者獲得更快的下載速度，並符合商店規範。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 受到大規模交付軟體的團隊信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/)，以及超過 100 家其他公司**的團隊，透過 Tuist 在其 iOS 與 Android 程式碼庫中更快交付軟體。
