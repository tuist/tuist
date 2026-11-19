---
{
  "title": "Bundle 洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追踪 iOS 和 Android Bundle 大小，在发布前发现回归问题，并通过 Tuist Bundle Insights 保持应用精简。"
}
---
# Bundle 洞察 {#bundle-insights}

随着你为应用添加更多功能，Bundle 体积会不断增长。其中一部分增长不可避免，但很多并非如此：重复的资源、未使用的符号以及平台特定的冗余都会累积起来。Tuist Bundle Insights 同时支持 **Apple** 和 **Android** Bundle，提供工具和洞察帮助你控制应用体积，并跟踪其随时间的变化趋势。

<.home_cards>
  <.home_card
    title="Apple"
    details="分析 iOS、macOS、watchOS 和 tvOS 应用的 .ipa、.xcarchive 和 .app Bundle。"
    link="/guides/features/bundle-insights/apple"
    supported_for="apple"
/>
  <.home_card
    title="Android"
    details="分析 Android 应用的 .aab 和 .apk Bundle。"
    link="/guides/features/bundle-insights/android"
    supported_for="android"
/>
</.home_cards>
