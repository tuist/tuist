---
{
  "title": "什麼是 Tuist？",
  "description": "開發者的虛擬平台團隊。為 Xcode、Gradle、Bazel、Elixir、Rust 與 Once 建置基礎設施，並提供針對各工具鏈量身打造的功能。"
}
---

# 為交付軟體的開發者打造的虛擬平台團隊

**Tuist 協助團隊擴展應用程式開發並加速交付**，將大型程式碼庫的複雜性轉化為能隨團隊成長的高效體驗。它與你已使用的建置系統相容，適用於 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 專案。可用功能取決於你的工具鏈：Rust 專案可獲得 Cargo 建置與測試洞察，包含文件測試、不穩定測試偵測，以及實驗性編譯快取。Once 則原生支援共用快取、建置與測試洞察、分片執行，以及受支援的應用程式預覽。

依照你的建置系統，選擇其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可直接連線，無需安裝 Tuist CLI；其他路徑會說明需要安裝哪些 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="在團隊與 CI 之間共用建置產出。支援 Xcode 編譯快取、Tuist 模組快取、Gradle 建置快取、Bazel 遠端快取、Elixir 相依性快取、Rust 實驗性編譯快取，以及 Once 共用動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="建置與測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 專案中的建置與測試耗時、失敗、不穩定性與回歸問題。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="僅執行受變更影響的測試，讓回饋在數秒內到位。適用於產生的 Xcode 專案。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="在受管制的 macOS 與 Linux 執行器上執行 CI，靠近開發者機器使用的相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過網址立即分享你的應用程式。無需等待商店審查，也無需複雜設定。"
    link="/guides/features/previews"
/>
  <.home_card
    title="產生的專案"
    details="以 Swift 描述 Xcode 專案並一致地產生它們。消除合併衝突並啟用模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="借助由 Tuist 快取網路支援的註冊表，在數秒內解析 Swift 套件，而非數分鐘。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="分析並保持應用程式輕量，讓使用者下載更快，並符合商店規範。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 受到大規模交付軟體團隊的信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 等團隊，以及 100 多家其他公司**透過 Tuist 在其 iOS 與 Android 程式碼庫中加速交付。
