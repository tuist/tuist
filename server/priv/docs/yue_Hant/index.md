---
{
  "title": "乜嘢係 Tuist？",
  "description": "專為開發者而設的虛擬平台團隊。為 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 打造基礎設施，並提供針對各工具鏈度身訂造的功能。"
}
---

# 專為交付軟體嘅開發者而設嘅虛擬平台團隊

**Tuist 協助團隊擴展應用程式開發並加快交付**，將大型代碼庫嘅複雜性轉化為隨團隊成長嘅高效體驗。它支援你已經使用嘅構建系統，適用於 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 項目。可用功能取決於你嘅工具鏈：Rust 項目可獲得 Cargo 構建同測試洞察，包括文檔測試、不穩定測試檢測同實驗性編譯緩存。Once 原生連接以支援共享緩存、構建同測試洞察、分片以及受支援嘅應用程式預覽。

跟隨適合你構建系統嘅其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可直接連接而無需 Tuist CLI；其他路徑會說明需要安裝邊啲 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="緩存"
    details="喺你嘅團隊同 CI 之間共享構建輸出。支援 Xcode 嘅編譯緩存、Tuist 嘅模塊緩存、Gradle 嘅構建緩存、Bazel 嘅遠程緩存、Elixir 嘅依賴緩存、Rust 嘅實驗性編譯緩存，以及 Once 嘅共享操作緩存。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="構建同測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 項目中嘅構建同測試時長、失敗、不穩定性及回歸問題。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="只運行受生成嘅 Xcode 項目變更影響嘅測試，讓反饋喺幾秒內到位。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runner"
    details="喺受管理嘅 macOS 同 Linux Runner 上運行 CI，靠近開發者機器使用嘅相同緩存。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過 URL 即時分享你嘅應用程式。無需應用商店審核延誤，亦無需複雜設置。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成項目"
    details="用 Swift 描述 Xcode 項目並一致地生成它們。消除合併衝突並解鎖模塊緩存。"
    link="/guides/features/projects"
/>
  <.home_card
    title="Package Registry"
    details="藉助由 Tuist 緩存網絡支援嘅註冊表，喺幾秒而非幾分鐘內解析 Swift 包。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Bundle 大小"
    details="分析並保持你嘅應用程式輕量，令用戶獲得更快嘅下載速度，同時符合應用商店指引。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體嘅團隊信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 及 100+ 其他公司嘅團隊**透過 Tuist 加快佢哋 iOS 同 Android 代碼庫嘅交付速度。
