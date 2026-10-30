---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Cache 優化構建時間，包括模組快取、Xcode 快取、Gradle 快取、Bazel 快取、Elixir 依賴項快取，以及實驗性的 Rust 編譯快取。"
}
---
# 快取 {#cache}

編譯產物不會在不同環境之間共用，令你不斷重複編譯相同代碼。Tuist 的快取功能會遠端共用這些產物，讓你的團隊和 CI 無需重新編譯已編譯過的內容，從而加快構建速度。

了解配合你項目或部署模式的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="為使用 Tuist 生成項目的專案，將個別模組以二進位形式快取。需要 Tuist 項目生成功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 項目，無需項目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 構建快取產物。包含構建洞察，助你掌握效能表現。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的 Remote Execution API 快取，以便在團隊和 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 依賴項啟用快取，並繼續使用 Mix。在儀表板中檢視快取命中和傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="在本機及透過 Kura 重用支援的註冊表葉庫輸出。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="自行託管"
    details="在靠近 CI、辦公室或區域運算資源的位置運行快取節點，並將它們連接至託管或自行託管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於執行器的私人網絡內，並與開發人員機器使用的同一快取共用，因此 CI 作業開箱即用即可獲得暖快取命中，無需單獨預熱 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發人員設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中打開帳戶的 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 和帳戶令牌**。此後，透過登入會話驗證的成員仍可從快取下載，但上傳需要 CI OIDC 驗證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶令牌。

當 CI 是受信任的快取生產者，而本機機器只應消費快取時，請使用此設定。該設定僅影響快取上傳授權。
