---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# 快取記憶體{#cache}

Xcode 的建立系統提供
[增量建立](https://en.wikipedia.org/wiki/Incremental_build_model)，可提高單一電腦上的效率。但是，建立工件無法在不同環境中共用，因此您必須反覆重建相同的程式碼
- 不論是在 [Continuous Integration (CI)
環境](https://en.wikipedia.org/wiki/Continuous_integration)，或是在本機開發環境 (Mac) 中。

Tuist 藉由快取功能解決這些挑戰，大幅縮短本機開發及 CI 環境的建置時間。這種方法不僅加速了回饋迴圈，還將情境切換的需求降至最低，最終提升了生產力。

我們提供兩種快取方式：
- <LocalizedLink href="/guides/features/cache/module-cache">模組快取</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode 快取</LocalizedLink>

## 模組快取{#module-cache}

對於使用 Tuist 的 <LocalizedLink href="/guides/features/projects">專案產生</LocalizedLink> 功能的專案，我們提供了強大的快取記憶體系統，可將個別模組快取為二進位檔案，並在團隊和 CI 環境中分享。

雖然您也可以使用新的 Xcode
快取，但此功能目前已針對本機建立進行最佳化，與產生的專案快取相比，您可能會有較低的快取命中率。但是，決定使用哪種快取解決方案取決於您的特定需求和偏好。您也可以結合兩種快取解決方案，以達到最佳效果。

<LocalizedLink href="/guides/features/cache/module-cache">進一步瞭解模組快取 →</LocalizedLink>

## Xcode 快取{#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode 快取目前已針對本機增量建置進行最佳化，且整個建置任務範圍尚未與路徑無關。不過您還是可以透過插入 Tuist
的遠端快取體驗到好處，而且我們預期隨著時間的推移，建立時間會隨著建立系統能力的不斷提升而改善。
<!-- -->
:::

Apple 一直致力於在建立層級開發新的快取解決方案，類似於 Bazel 和 Buck 等其他建立系統。新的快取功能自 Xcode 26 開始提供，Tuist 現在可與之無縫整合 - 無論您是否使用 Tuist 的 <LocalizedLink href="/guides/features/projects">專案產生</LocalizedLink> 功能。

<LocalizedLink href="/guides/features/cache/xcode-cache">進一步瞭解 Xcode 快取 →</LocalizedLink>
