---
{
  "title": "建置洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 建置洞察，追蹤 Xcode、Gradle、Bazel、Elixir、Rust 和 Once 專案的建置效能。"
}
---
# 建置洞察 {#build-insights}

使用建置洞察追蹤本機與 CI 建置效能。目前支援 Xcode、Gradle、Bazel、Elixir、Rust 與 Once。若要逐步調查建置緩慢與 CI 成本上升的問題，請參閱 [Slow builds](https://tuist.dev/solutions/slow-builds) 與 [CI costs](https://tuist.dev/solutions/ci-costs)。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在 Tuist 儀表板中追蹤 Xcode scheme 的後續動作耗時、建置設定與建置中繼資料。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="產生的專案"
    details="在 Tuist 產生的專案中，透過自訂 scheme 追蹤建置洞察。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="使用 Tuist Gradle 外掛程式追蹤 Gradle 任務耗時與快取成效。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 Build Event Protocol 追蹤 Bazel 指令持續時間、快取總計與關鍵路徑診斷。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="追蹤 Elixir 專案的編譯耗時、警告，以及拖慢建置的檔案。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用 Tuist CLI 追蹤 Cargo 指令持續時間、觀察到的 rustc 呼叫，以及編譯器診斷。"
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="即時追蹤執行，並檢查圖形動作、持續時間、失敗與快取決策。"
    link="/guides/features/build-insights/once"
/>
</.home_cards>
