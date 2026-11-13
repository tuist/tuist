---
{
  "title": "乜嘢係 Tuist？",
  "description": "Tuist 係一個為工程團隊同佢哋嘅編碼代理而設嘅建構平台。支援跨 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅建構同測試工作流程；Once 支援處於 canary 階段。功能因工具鏈而異，Rust 編譯快取仍屬實驗性。"
}
---

# 團隊同編碼代理專用嘅建構平台

**Tuist 係一個專為工程團隊同佢哋嘅編碼代理而設嘅建構平台。** 支援 Xcode、Gradle、Bazel、Elixir 同 Rust 嘅建構同測試工作流程；Once 支援目前處於 Canary 階段。佢會配合你已經用開嘅建構系統，而唔係取代佢哋。可用功能取決於你嘅工具鏈：Rust 項目可以取得 Cargo 建構同測試洞察，包括 doctests、不穩定測試偵測，以及實驗性編譯快取。Once 會原生連接，提供共享快取、建構同測試洞察、分片處理，以及支援嘅應用程式預覽。

根據你嘅建構系統，跟隨其中一條<.localized_link href="/guides/get-started">入門路徑</.localized_link>。Once 可以直接連接，無需 Tuist CLI；其他路徑會說明需要安裝邊啲 Tuist 工具。

<br/>

<.home_cards>
  <.home_card
    title="快取"
    details="喺團隊同 CI 之間共享建構輸出。支援 Xcode 編譯快取、Tuist 模組快取、Gradle 建構快取、Bazel 遠端快取、Elixir 依賴快取、Rust 實驗性編譯快取，以及 Once 共享動作快取。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="建構同測試洞察"
    details="追蹤 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 項目嘅建構同測試持續時間、失敗、不穩定性同回歸問題。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選擇性測試"
    details="喺生成嘅 Xcode 項目中跳過未變更嘅測試目標，並提供早期訪問覆蓋策略，以支援個別 XCTest/XCUITest 選擇。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="執行器"
    details="喺受管理嘅 macOS 同 Linux 執行器上運行 CI，靠近開發者機器使用嘅同一快取。"
    link="/guides/features/runners"
/>
  <.home_card
    title="預覽"
    details="透過 URL 分享支援嘅流動應用程式、macOS 應用程式，以及 macOS/Linux 命令行工具。需符合建構、簽署同接收者兼容性要求。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成項目"
    details="用 Swift 描述 Xcode 項目並一致地生成佢哋。減少項目文件衝突並解鎖模組快取。"
    link="/guides/features/projects"
/>
  <.home_card
    title="套件註冊表"
    details="透過註冊表協議獲取支援嘅 Swift 套件，而唔係克隆佢哋嘅 Git 儲存庫。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="套件大小"
    details="隨時間追蹤支援嘅 Apple 同 Android 套件大小，並調查大小回歸問題。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 獲大規模交付軟件嘅團隊信賴

閱讀[客戶故事](https://tuist.dev/customers)，了解團隊採用嘅工作流程同佢哋報告嘅成果。
