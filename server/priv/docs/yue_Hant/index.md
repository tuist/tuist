---
{
  "title": "乜嘢係 Tuist？",
  "description": "Tuist 係一個為工程團隊同佢哋嘅編碼代理而設嘅構建平台。佢支援跨 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅構建同測試工作流程；Once 支援目前處於 canary 階段。功能會因應工具鏈而異，而 Rust 編譯快取功能仍屬實驗性質。"
}
---

# 團隊同編碼代理專用嘅建構平台

**Tuist 係專為工程團隊同佢哋嘅編碼代理而設嘅建構平台。** 支援 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅建構同測試工作流程；Once 支援目前處於 canary 階段。Tuist 會配合你已經使用緊嘅建構系統，而唔係取代佢哋。可用功能取決於你嘅工具鏈：Rust 專案可以獲得 Cargo 建構同測試洞察，包括 doctests、不穩定測試偵測，以及實驗性編譯快取。Once 會原生連接，提供共享快取、建構同測試洞察、分片，以及支援應用程式預覽。

根據你嘅建構系統，跟隨其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可以直接連接，無需 Tuist CLI；其他路徑會說明需要安裝邊啲 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="喺團隊同 CI 之間共享建構輸出。支援 Xcode 嘅編譯快取、Tuist 嘅模組快取、Gradle 嘅建構快取、Bazel 嘅遠端快取、Elixir 嘅依賴快取、Rust 嘅實驗性編譯快取，以及 Once 嘅共享動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="建構同測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 專案嘅建構同測試持續時間、失敗、不穩定性同倒退情況。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="只運行受生成 Xcode 專案變更影響嘅測試，讓反饋喺幾秒內就到達。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="喺受管理嘅 macOS 同 Linux 執行器上運行 CI，靠近開發者機器使用嘅同一快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="用一個 URL 即時分享你嘅應用程式。無需應用商店審核延誤，亦無需複雜設定。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成專案"
    details="用 Swift 描述 Xcode 專案並一致地生成佢哋。消除合併衝突並解鎖模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過由 Tuist 快取網絡支援嘅註冊表，喺幾秒內而非幾分鐘內解析 Swift 套件。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="分析並保持你嘅應用程式輕量，令用戶獲得更快嘅下載速度，同時符合應用商店指引。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟件嘅團隊信賴

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/) 等同超過 100 間公司嘅團隊**透過 Tuist 喺 iOS 同 Android 代碼庫上更快交付軟件。
