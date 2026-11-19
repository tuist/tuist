---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Cache 優化 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 嘅建構時間。"
}
---
# 快取 {#cache}

建構產物不會跨環境共用，導致你反覆重新建構相同程式碼。Tuist 的快取功能會遠端共用產物，讓團隊與 CI 無需重建已建構過的內容即可獲得更快的建構速度。如要了解本機與遠端建構快取在不同建構系統中的運作方式，以及 Xcode 自身的快取機制，請參閱 <.localized_link href="/references/concepts/build-cache">甚麼是建構快取？</.localized_link>。如在選擇快取方案前想釐清建構緩慢的原因，請參閱 [建構緩慢](https://tuist.dev/solutions/slow-builds)。

了解符合你的專案或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位形式快取，適用於使用 Tuist 產生專案的專案。需要透過 Tuist 產生專案。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="跨環境共用 Xcode 編譯產物。適用於任何 Xcode 專案，無需產生專案。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 建構快取產物。包含建構洞察，助你掌握效能表現。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的 Remote Execution API 快取，以在團隊與 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 相依套件啟用快取，並繼續使用 Mix。在儀表板中查看快取命中與傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="在本機及透過 Kura 重複使用支援的 Rust 編譯輸出與建構腳本執行結果。了解如何啟用快取並檢查快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once 快取"
    details="透過 Once 的原生 Tuist 提供者，在開發者機器與 CI 之間共用已快取的腳本與圖形動作結果。"
    link="/guides/features/cache/once"
/>
  <.home_card
    title="自行託管"
    details="在靠近 CI、辦公室或區域運算資源的位置執行快取節點，並將它們連接至託管或自行託管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於 runner 的私人網路內，並與開發者機器使用的同一快取共用，因此 CI 工作預設即可獲得溫快取命中，無需另外預熱 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可將開發者設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳戶的 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 與帳戶權杖**。此後，透過登入工作階段驗證的成員仍可從快取下載，但上傳需要 CI OIDC 驗證或具備快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶權杖。

當 CI 是可信的快取生產者，而本機機器只應消費快取時使用此設定。此設定僅影響快取上傳授權。
