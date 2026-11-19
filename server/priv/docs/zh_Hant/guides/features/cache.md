---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Cache 優化 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo 的建置時間。"
}
---
# 快取 {#cache}

建置產物不會在不同環境之間共用，導致你必須反覆重新建置相同的程式碼。Tuist 的快取功能會遠端共用產物，讓你的團隊與 CI 能加快建置速度，無需重複建置已建置過的內容。若要了解本機與遠端建置快取在不同建置系統中的運作方式，以及 Xcode 自身的快取為何，請參閱 <.localized_link href="/references/concepts/build-cache">什麼是建置快取？</.localized_link>。若要在選擇快取前釐清建置緩慢的原因，請參閱 [建置緩慢](https://tuist.dev/solutions/slow-builds)。

學習符合你的專案或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位檔形式快取，適用於使用 Tuist 產生專案的專案。需要 Tuist 專案產生。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 專案，無需專案產生。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 建置快取產物。包含建置洞察，提供效能可見度。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的遠端執行 API 快取，以便在團隊與 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 相依性啟用快取，並繼續使用 Mix。在儀表板中檢視快取命中與傳輸。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性功能）"
    details="在本機與透過 Kura 重複使用支援的 Rust 編譯輸出與建置腳本執行。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Struo 快取"
    details="透過 Struo 的原生 Tuist 提供者，在開發者機器與 CI 之間共用已快取的腳本與圖形動作結果。"
    link="/guides/features/cache/struo"
/>
  <.home_card
    title="自行託管"
    details="在靠近 CI、辦公室或區域運算資源的位置執行快取節點，並將它們連線至託管或自行託管的 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **在 Tuist Runners 上最快**
>
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於執行器的私有網路中，並與你的開發者機器使用的相同快取共用，因此 CI 工作預設即可獲得暖快取命中，無需另外預熱獨立的 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳號管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳號的 **快取** 設定，並將 **快取上傳存取權** 設為 **僅限 CI 與帳號權杖**。之後，透過登入工作階段驗證的成員仍可從快取下載，但上傳需要 CI OIDC 驗證或具備快取寫入範圍的帳號權杖，例如 `project:cache:write` 或 `ci`。

當 CI 是受信任的快取產生者，而本機機器應僅消費快取時使用此設定。此設定僅影響快取上傳授權。
