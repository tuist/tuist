---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Cache 為 Xcode、Gradle、Bazel、Elixir、Rust 同 Struo 優化構建時間。"
}
---
# 快取 {#cache}

建置產物唔會喺唔同環境之間共用，搞到你成日要重新建置同一啲代碼。Tuist 嘅快取功能會遠端共用產物，令你嘅團隊同 CI 可以加快建置速度，唔使重複建置已經建好嘅內容。想了解本地同遠端建置快取喺唔同建置系統中點樣運作，以及 Xcode 自身嘅快取係乜，請參閱 <.localized_link href="/references/concepts/build-cache">乜嘢係建置快取？</.localized_link>。如果想喺選擇快取之前搞清楚點解建置咁慢，請參閱 [緩慢嘅建置](https://tuist.dev/solutions/slow-builds)。

了解配合你項目或部署模型嘅快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進制形式快取，適用於使用 Tuist 生成項目嘅專案。需要 Tuist 項目生成功能。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="喺唔同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 項目，唔需要項目生成。"
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
    details="為支援嘅 Elixir 依賴項啟用快取，並繼續使用 Mix。喺儀表板中檢查快取命中同傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="重用支援嘅 Rust 編譯輸出同建置腳本執行結果，可喺本地或透過 Kura 進行。了解如何啟用快取同檢查快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Struo 快取"
    details="透過 Struo 嘅原生 Tuist 提供者，喺開發人員機器同 CI 之間共用已快取嘅腳本同圖形動作結果。"
    link="/guides/features/cache/struo"
/>
  <.home_card
    title="自行託管"
    details="喺靠近 CI、辦公室或區域運算資源嘅地方運行快取節點，並將佢哋連接到託管或自行託管嘅 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runners 上最快**
>
> 喺 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取位於 Runner 嘅私人網絡中，並與你開發人員機器使用嘅同一個快取共用，因此 CI 任務開箱即用即可獲得熱命中，無需單獨預熱 CI 快取。


## 限制僅向 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發人員設為唯讀，同時允許 CI 上傳快取產物。喺 Tuist 中打開帳戶嘅 **快取** 設定，並將 **快取上傳權限** 設為 **僅限 CI 同帳戶令牌**。之後，通過登入會話驗證嘅成員仍然可以從快取下載，但上傳需要 CI OIDC 驗證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）嘅帳戶令牌。

當 CI 係可信賴嘅快取生產者，而本地機器只應該消費快取時使用此設定。此設定僅影響快取上傳授權。
