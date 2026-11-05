---
{
  "title": "Bundle 洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追踪 iOS 和 Android Bundle 大小，在发布前发现回归问题，借助 Tuist Bundle Insights 保持应用精简。"
}
---
# 包分析 {#bundle-insights}

随着你为应用添加更多功能，包体积会不断增长。其中一部分增长不可避免，但很多是可以避免的：重复的资源、未使用的符号以及特定平台的冗余都会累积起来。Tuist Bundle Insights 同时支持 **Apple** 和 **Android** 包，为你提供工具和洞察，帮助控制应用体积，并跟踪其随时间的变化趋势。

<.home_cards>
  <.home_card
    title="Apple"
    details="分析适用于 iOS、macOS、watchOS 和 tvOS 应用的 .ipa、.xcarchive 和 .app 包。"
    link="/guides/features/bundle-insights/apple"
    supported_for="apple"
/>
  <.home_card
    title="Android"
    details="分析适用于 Android 应用的 .aab 和 .apk 包。"
    link="/guides/features/bundle-insights/android"
    supported_for="android"
/>
</.home_cards>
