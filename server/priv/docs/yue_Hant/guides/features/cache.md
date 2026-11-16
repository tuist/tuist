---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Cache 為 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 優化建置時間。"
}
---
# 快取 {#cache}

編譯產物不會在不同環境之間共用，令你不得不重複編譯同一份代碼。Tuist 的快取功能會遠端共用這些產物，讓你的團隊和 CI 無需重新編譯已編譯過的內容，從而加快構建速度。如要了解本機與遠端構建快取在不同構建系統中的運作方式，以及 Xcode 自身的快取機制，請參閱 <.localized_link href="/references/concepts/build-cache">什麼是構建快取？</.localized_link>。若要在選擇快取方案前找出構建緩慢的原因，請參閱 [構建緩慢](https://tuist.dev/solutions/slow-builds)。

了解符合你專案或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位形式快取，適用於使用 Tuist 生成專案的專案。需要透過 Tuist 生成專案。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 專案，無需生成專案。"
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
    details="在本機及透過 Kura 重用支援的 Rust 編譯輸出和構建腳本執行結果。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once 快取"
    details="透過 Once 的原生 Tuist 提供者，在開發者機器和 CI 之間共用已快取的腳本和圖動作結果。"
    link="/guides/features/cache/once"
/>
  <.home_card
    title="自行託管"
    details="在靠近 CI、辦公室或區域運算資源的位置運行快取節點，並將它們連接至託管或自行託管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上速度最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於 runner 的私有網絡中，並與開發者機器使用的同一快取共用，因此 CI 任務開箱即用即可獲得暖命中，無需另外預熱獨立的 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳戶的 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 和帳戶令牌**。此後，透過登入會話認證的成員仍可從快取下載，但上傳需要 CI OIDC 認證或具備快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶令牌。

當 CI 是受信任的快取生產者，而本機機器只應消費快取時，請使用此設定。此設定僅影響快取上傳授權。
