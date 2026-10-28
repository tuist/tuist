---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# 快取 {#cache}

構建產物不會在不同環境之間共享，導致你必須不斷重新構建相同的代碼。Tuist 的快取功能會遠端共享產物，讓你的團隊和 CI 無需重新構建已構建的內容，從而加快構建速度。

了解符合你的項目或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組快取為二進制檔案，適用於使用 Tuist 生成項目的專案。需要 Tuist 項目生成。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共享 Xcode 編譯產物。適用於任何 Xcode 項目，無需項目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共享 Gradle 構建快取產物。包含構建洞察，以提升性能可見性。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的遠端執行 API 快取，以便在你的團隊和 CI 之間共享動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 依賴項啟用快取，並繼續使用 Mix。在儀表板中檢查快取命中和傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="在本機和透過 Kura 重複使用支援的註冊表葉庫輸出。了解如何啟用快取並檢查快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="自託管"
    details="在靠近 CI、辦公室或區域計算資源的地方運行快取節點，並將它們連接到託管或自託管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於運行器的私有網絡中，並與開發人員機器使用的相同快取共享，因此 CI 作業開箱即用即可獲得溫暖命中，無需單獨預熱 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發人員設為只讀，同時允許 CI 上傳快取產物。在 Tuist 中打開帳戶的 **快取** 設置，並將 **快取上傳訪問權限** 設為 **僅限 CI 和帳戶令牌**。此後，通過登錄會話認證的成員仍然可以從快取下載，但上傳需要 CI OIDC 認證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶令牌。

當 CI 是受信任的快取生產者且本機機器僅應消費快取時，請使用此設置。該設置僅影響快取上傳授權。
