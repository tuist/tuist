---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Cache 優化建置時間，支援模組快取、Xcode 快取、Gradle 快取、Bazel 快取、Elixir 依賴項快取，以及實驗性 Rust 編譯快取。"
}
---
# 快取 {#cache}

建置產物不會在不同環境之間共用，導致你要重複建置相同嘅程式碼。Tuist 嘅快取功能會遠端共用產物，令你嘅團隊同 CI 可以加快建置速度，無須重新建置已經建置好嘅內容。

了解配合你專案或部署模型嘅快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="為使用 Tuist 產生專案嘅專案，將個別模組以二進位形式快取。需要 Tuist 專案產生功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 專案，無須產生專案。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠端共用 Gradle 建置快取產物。包含建置洞察，提供效能可見度。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 嘅 Remote Execution API 快取，以便喺你嘅團隊同 CI 之間共用動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援嘅 Elixir 依賴項啟用快取，並繼續使用 Mix。喺儀表板檢視快取命中同傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="重用支援嘅 Rust 編譯輸出同建置腳本執行，包括本地同透過 Kura。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="自行託管"
    details="將快取節點運行於靠近 CI、辦公室或區域運算資源嘅位置，並將佢哋連接至託管或自行託管嘅 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **喺 Tuist Runners 上最快**
>
> 喺 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取會 colocated 喺 runner 嘅私人網絡，並同你開發者機器使用嘅同一個快取共用，因此 CI 工作預設即可獲得暖命中，無須另外預熱 CI 快取。


## 限制上傳至 CI {#restrict-uploads-to-ci}

帳戶管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。喺 Tuist 開啟帳戶嘅 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 同帳戶令牌**。之後，透過登入會話認證嘅成員仍然可以從快取下載，但上傳需要 CI OIDC 認證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）嘅帳戶令牌。

當 CI 係可信賴嘅快取生產者，而本地機器只應消耗快取時，請使用此設定。此設定只影響快取上傳授權。
