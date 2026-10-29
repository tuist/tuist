---
{
  "title": "構建洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Build Insights 追蹤 Xcode、Gradle、Bazel、Elixir 同 Rust 項目嘅構建效能。"
}
---
# 構建洞察 {#build-insights}

使用 Build Insights 追蹤本機和 CI 構建效能。目前支援 Xcode、Gradle、Bazel、Elixir 和 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在 Tuist 儀表板中追蹤 Xcode scheme 的後續動作耗時、構建設置和構建元數據。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成的項目"
    details="在帶有自定義 scheme 的 Tuist 生成項目中追蹤構建洞察。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="透過 Tuist Gradle 插件追蹤 Gradle 任務耗時和快取效率。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 Build Event Protocol 追蹤 Bazel 指令持續時間、快取總數和關鍵路徑診斷。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="追蹤你的 Elixir 項目編譯所需時間、警告以及拖慢構建的文件。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="透過 Tuist CLI 追蹤 Cargo 指令持續時間、觀察到的 rustc 調用和編譯器診斷。"
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
