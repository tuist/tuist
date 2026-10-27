---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# 快取 {#cache}

建置產物不會在不同環境之間共用，導致你必須反覆重新建置相同的程式碼。Tuist 的快取功能可遠端共用產物，讓你的團隊與 CI 能獲得更快的建置速度，無須重新建置已建置過的內容。

了解符合你的專案或部署模型的快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位形式快取，適用於使用 Tuist 產生之專案的專案。需要 Tuist 專案產生。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 專案，無需專案產生。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 建置快取產物。包含建置洞察，以提升效能可見度。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 的 Remote Execution API 快取，以在你的團隊與 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援的 Elixir 相依套件啟用快取，並繼續使用 Mix。在儀表板中檢查快取命中與傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="在本機及透過 Kura 重複使用支援的註冊表葉節點程式庫輸出。了解如何啟用快取並檢查快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
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
> 在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於執行器的私人網路中，並與開發人員機器使用的相同快取共用，因此 CI 工作從一開始就能獲得溫暖命中，無需另外預熱獨立的 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發人員設為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳戶的 **快取** 設定，並將 **快取上傳存取權** 設為 **僅限 CI 與帳戶權杖**。之後，透過登入工作階段驗證的成員仍可從快取下載，但上傳需要 CI OIDC 驗證或具備快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶權杖。

當 CI 是受信任的快取生產者，而本機機器應僅消費快取時，請使用此設定。此設定僅影響快取上傳授權。
