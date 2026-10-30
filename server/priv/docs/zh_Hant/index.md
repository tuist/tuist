---
{
  "title": "什麼是 Tuist？",
  "description": "開發者的虛擬平台團隊。為 Xcode、Gradle、Bazel、Elixir 與 Rust 建置基礎設施，並提供針對各工具鏈量身打造的功能。"
}
---

# 為交付軟體的開發者打造的虛擬平台團隊

**Tuist 協助團隊擴展應用程式開發並加速交付**，將大型程式碼庫的複雜性轉化為隨團隊成長的高效體驗。它與你已使用的建置系統相容，支援 Xcode、Gradle、Bazel、Elixir 和 Rust 專案。可用功能取決於你的工具鏈：Rust 專案可獲得 Cargo 建置與測試洞察，包含文件測試、不穩定測試偵測，以及實驗性的編譯快取。

首先<.localized_link href="/guides/install-tuist">安裝 Tuist 命令列介面</.localized_link>，然後依照適用於你建置系統的<.localized_link href="/guides/get-started">入門指南</.localized_link>進行操作。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共享編譯輸出。支援 Xcode 的編譯快取、Tuist 的模組快取、Gradle 的建置快取、Bazel 的遠端快取，以及 Rust 的實驗性編譯快取。"
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="建置與測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir 和 Rust 專案中的建置與測試耗時、失敗、不穩定性以及回歸問題。"
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="僅執行受變更影響的測試，適用於 Xcode 與產生的專案，讓回饋在數秒內到位。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管制的 macOS 與 Linux 執行器上執行 CI，靠近開發者機器所使用的相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過網址即時分享你的應用程式。無需等待商店審查，也無需複雜設定。"
    link="/guides/features/previews"
/>
  <.home_card
    title="產生的專案"
    details="以 Swift 描述 Xcode 專案並一致地產生它們。消除合併衝突並啟用模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="藉由由 Tuist 快取網路支援的註冊表，在數秒而非數分鐘內解析 Swift 套件。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="分析並保持應用程式精簡，讓使用者獲得更快的下載速度，並符合商店規範。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體的團隊信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 等超過 100 家公司的團隊**透過 Tuist 在其 iOS 與 Android 程式碼庫中加速交付。
