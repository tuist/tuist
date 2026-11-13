---
{
  "title": "快取",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Cache 優化 Xcode、Gradle、Bazel、Elixir、Rust 同 Once 嘅建構時間。"
}
---
# 快取 {#cache}

編譯產物唔會喺唔同環境之間共享，令你被迫重複編譯相同嘅代碼。Tuist 嘅快取功能會遠程共享產物，令你嘅團隊同 CI 可以更快完成編譯，而唔使重新編譯已經編譯過嘅內容。想喺選擇快取之前了解點解編譯咁慢，請參閱 [Slow builds](https://tuist.dev/solutions/slow-builds)。

了解符合你項目或部署模式嘅快取工作流程：

<.home_cards>
  <.home_card
    title="模組快取"
    details="將個別模組以二進制形式快取，適用於使用 Tuist 生成項目嘅項目。需要 Tuist 項目生成。"
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode 快取"
    details="喺唔同環境之間共享 Xcode 編譯產物。適用於任何 Xcode 項目，無需項目生成。"
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle 快取"
    details="遠程共享 Gradle 編譯快取產物。包含編譯洞察，助你了解效能表現。"
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel 快取"
    details="將 Bazel 指向 Tuist 嘅 Remote Execution API 快取，以便喺你嘅團隊同 CI 之間共享動作輸出。"
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir 快取"
    details="為支援嘅 Elixir 依賴項啟用快取，並繼續使用 Mix。喺儀表板中檢視快取命中同傳輸情況。"
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust 快取（實驗性）"
    details="喺本地同透過 Kura 重用支援嘅 Rust 編譯輸出同構建腳本運行結果。了解如何啟用快取並檢視快取活動。"
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once 快取"
    details="透過 Once 嘅原生 Tuist 提供者，喺開發者機器同 CI 之間共享已快取嘅腳本同圖動作結果。"
    link="/guides/features/cache/once"
/>
  <.home_card
    title="自託管"
    details="將快取節點運行喺靠近 CI、辦公室或區域運算資源嘅位置，並將佢哋連接至託管或自託管嘅 Tuist。"
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **喺 Tuist Runners 上最快**
>
> 喺 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上，快取會 colocated 喺 runner 嘅私有網絡上，並與你開發者機器使用嘅同一個快取共享，因此 CI 任務開箱即用即可獲得熱命中，無需單獨預熱 CI 快取。


## 限制上傳至 CI {#restrict-uploads-to-ci}

帳戶管理員可以將開發者設為唯讀，同時允許 CI 上傳快取產物。喺 Tuist 中打開帳戶嘅 **Cache** 設定，並將 **Cache upload access** 設為 **CI and account tokens only**。之後，透過登入會話驗證嘅成員仍然可以從快取下載，但上傳需要 CI OIDC 驗證或具有快取寫入權限（例如 `project:cache:write` 或 `ci`）嘅帳戶令牌。

當 CI 係可信賴嘅快取生產者，而本地機器只應消費快取時，請使用此設定。此設定僅影響快取上傳授權。
