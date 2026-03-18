---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# 快取{#cache}

Xcode 的建置系統提供
[增量建置](https://en.wikipedia.org/wiki/Incremental_build_model)，可提升單一機器的建置效率。然而，建置產出物並不會在不同環境間共享，這會迫使您必須反覆重新建置相同的程式碼——無論是在您的
[持續整合 (CI) 環境](https://en.wikipedia.org/wiki/Continuous_integration) 還是本地開發環境（您的
Mac）中。

Tuist 透過其快取功能解決了這些挑戰，大幅縮短了本地開發與 CI
環境中的建置時間。此方法不僅加速了回饋循環，還將上下文切換的需求降至最低，最終提升了生產力。

我們提供兩種快取類型：
- <LocalizedLink href="/guides/features/cache/module-cache">模組快取</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode
  快取</LocalizedLink>

## 模組快取{#module-cache}

對於使用 Tuist
<LocalizedLink href="/guides/features/projects">專案生成</LocalizedLink>功能的專案，我們提供強大的快取系統，該系統會將個別模組快取為二進位檔，並在您的團隊及
CI 環境間共享。

雖然您也可以使用新的 Xcode
快取功能，但此功能目前主要針對本地建置進行優化，因此與生成的專案快取相比，您的快取命中率可能會較低。不過，選擇使用哪種快取方案取決於您的具體需求與偏好。您也可以結合這兩種快取方案，以獲得最佳效果。

<LocalizedLink href="/guides/features/cache/module-cache">進一步了解模組快取
→</LocalizedLink>

## Xcode 快取{#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode 的快取機制目前針對本地增量建置進行了優化，且尚未實現所有建置任務的路徑獨立性。儘管如此，您仍可透過整合 Tuist
的遠端快取來獲得效益，我們預期隨著建置系統功能的持續改進，建置時間將逐步縮短。
<!-- -->
:::

Apple 一直在開發一種基於建置層級的新快取解決方案，類似於 Bazel 和 Buck 等其他建置系統。這項新的快取功能自 Xcode 26 起已可使用，而
Tuist 現已與其無縫整合——無論您是否使用 Tuist 的
<LocalizedLink href="/guides/features/projects">專案生成</LocalizedLink>功能。

<LocalizedLink href="/guides/features/cache/xcode-cache">進一步了解 Xcode 快取
→</LocalizedLink>
