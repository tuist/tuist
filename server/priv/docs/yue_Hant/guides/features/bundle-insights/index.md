---
{
  "title": "Bundle 分析",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤 iOS 和 Android Bundle 大小，在發布前發現體積回歸，並透過 Tuist Bundle Insights 保持應用程式精簡。"
}
---
# 套件分析 {#bundle-insights}

當你為應用程式加入更多功能時，套件體積會不斷增加。部分增長無可避免，但許多其實可以避免：重複的資源、未使用的符號，以及平台特定的浪費都會累積起來。Tuist Bundle Insights 同時支援 **Apple** 和 **Android** 套件，提供工具和分析結果，助你保持應用程式體積小巧，並追蹤其隨時間的變化趨勢。

<.home_cards>
  <.home_card
    title="Apple"
    details="分析 iOS、macOS、watchOS 和 tvOS 應用程式的 .ipa、.xcarchive 和 .app 套件。"
    link="/guides/features/bundle-insights/apple"
    supported_for="apple"
/>
  <.home_card
    title="Android"
    details="分析 Android 應用程式的 .aab 和 .apk 套件。"
    link="/guides/features/bundle-insights/android"
    supported_for="android"
/>
</.home_cards>
