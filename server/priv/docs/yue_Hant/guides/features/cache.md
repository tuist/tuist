---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Cache 優化 Xcode、Gradle、Bazel、Elixir、Rust 同 Struo 嘅建構時間。"
}
---
# 快取 {#cache}

建構產物不會在不同環境之間共享，令你被迫重複建構相同程式碼。Tuist 的快取功能會遠端共享產物，讓你的團隊和 CI 無需重新建構已建構過的內容，從而獲得更快的建構速度。如要了解本機和遠端建構快取如何在不同建構系統中運作，以及 Xcode 自身的快取是什麼，請參閱 <.localized_link href="/references/concepts/build-cache">什麼是建構快取？</.localized_link>。如在選擇快取前想找出建構緩慢的原因，請參閱 [建構緩慢](https://tuist.dev/solutions/slow-builds)。

了解符合你專案或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位形式快取，適用於使用 Tuist 生成專案的專案。需要 Tuist 專案生成功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共享 Xcode 編譯產物。適用於任何 Xcode 專案，無需專案生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共享 Gradle 建構快取產物。包含建構洞察，助你掌握效能表現。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的 Remote Execution API 快取，以便在團隊和 CI 之間共享動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 依賴項啟用快取，並繼續使用 Mix。在儀表板中檢視快取命中和傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="在本機及透過 Kura 重用支援的 Rust 編譯輸出和建構腳本執行結果。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Struo 快取"
    details="透過 Struo 的原生 Tuist 提供者，在開發者機器和 CI 之間共享已快取的腳本和圖形動作結果。"
    link="/guides/features/cache/struo"
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
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於 runner 的私人網絡中，並與你的開發者機器使用的同一快取共享，因此 CI 工作無需預熱即可立即獲得暖命中，無須另外預熱獨立的 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳戶的 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 和帳戶令牌**。之後，透過登入會話驗證的成員仍可從快取下載，但上傳需要 CI OIDC 驗證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶令牌。

當 CI 是可信的快取生產者，而本機機器只應消費快取時，請使用此設定。此設定僅影響快取上傳授權。
