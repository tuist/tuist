---
{
  "title": "乜嘢係 Tuist？",
  "description": "開發人員嘅虛擬平台團隊。為 Xcode、Gradle、Bazel、Elixir 同 Rust 構建基礎設施，並提供針對每個工具鏈度身訂造嘅功能。"
}
---

# 專為交付軟體嘅開發者而設嘅虛擬平台團隊

**Tuist 協助團隊擴展應用程式開發同加快交付速度**，將大型代碼庫嘅複雜性轉化為隨團隊成長嘅高效體驗。它支援你已經使用嘅構建系統，適用於 Xcode、Gradle、Bazel、Elixir 同 Rust 項目。可用功能取決於你嘅工具鏈：Rust 項目可獲得 Cargo 構建同測試洞察，包括文檔測試、不穩定測試檢測同實驗性編譯快取。

首先 <.localized_link href="/guides/install-tuist">安裝 Tuist 命令行界面</.localized_link>，然後根據你嘅構建系統跟隨其中一個 <.localized_link href="/guides/get-started">入門指南</.localized_link>。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="喺團隊同 CI 之間共享編譯輸出。支援 Xcode 嘅編譯快取、Tuist 嘅模組快取、Gradle 嘅構建快取、Bazel 嘅遠端快取，以及 Rust 嘅實驗性編譯快取。"
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="構建同測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir 同 Rust 項目中嘅構建同測試時長、失敗、不穩定性同回歸問題。"
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="只運行受變更影響嘅測試，適用於 Xcode 同生成嘅項目，讓反饋喺幾秒內完成。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="喺受管理嘅 macOS 同 Linux 執行器上運行 CI，貼近開發者機器使用嘅相同快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過 URL 即時分享你嘅應用程式。無需應用商店審核延誤，無需複雜設置。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成嘅項目"
    details="用 Swift 描述 Xcode 項目並一致地生成它們。消除合併衝突並解鎖模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過由 Tuist 快取網絡支援嘅註冊表，喺幾秒而非幾分鐘內解析 Swift 套件。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="應用程式包大小"
    details="分析並保持你嘅應用程式輕量，讓用戶獲得更快嘅下載速度，同時符合應用商店指引。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟體嘅團隊信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 等同超過 100 間其他公司嘅團隊** 透過 Tuist 喺 iOS 同 Android 代碼庫上加快交付速度。
