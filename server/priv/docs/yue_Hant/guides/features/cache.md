---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "利用 Tuist Cache 優化建置時間，包括模組快取、Xcode 快取、Gradle 快取、Bazel 快取、Elixir 依賴項快取，以及實驗性的 Rust 編譯快取。"
}
---
# 快取 {#cache}

編譯產物唔會喺唔同環境之間共用，搞到你成日要重複編譯同一份代碼。Tuist 嘅快取功能會將產物遠端共用，令你嘅團隊同 CI 可以加快編譯速度，唔使重新編譯已經編譯過嘅內容。

了解配合你項目或部署模式嘅快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進位形式快取，適用於使用 Tuist 生成項目嘅專案。需要透過 Tuist 生成項目。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="喺唔同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 項目，無須生成項目。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 編譯快取產物。包含編譯洞察，助你了解效能表現。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 嘅 Remote Execution API 快取，以便喺團隊同 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援嘅 Elixir 依賴項啟用快取，並繼續使用 Mix。你可以喺儀表板檢視快取命中同傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="喺本機及透過 Kura 重用受支援嘅註冊表葉庫輸出。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="自行託管"
    details="將快取節點部署於靠近 CI、辦公室或區域運算資源嘅位置，並將佢哋連接至託管或自行託管嘅 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **喺 Tuist Runners 上最快**
>
> 喺 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取會放置於執行器嘅私人網絡，並與開發者機器所用嘅快取共用，因此 CI 工作無需額外預熱即可獲得高效快取命中，亦無須單獨預熱 CI 快取。


## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。喺 Tuist 開啟帳戶嘅 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 同帳戶令牌**。之後，透過登入會話驗證嘅成員仍然可以從快取下載，但上傳需要 CI OIDC 驗證或具備快取寫入範圍（例如 `project:cache:write` 或 `ci`）嘅帳戶令牌。

當 CI 係可信賴嘅快取來源，而本機機器只應消費快取時，請使用此設定。此設定僅影響快取上傳授權。
