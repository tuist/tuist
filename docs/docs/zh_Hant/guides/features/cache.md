---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# 快取{#cache}

Xcode 的建置系統提供 [增量建置](https://en.wikipedia.org/wiki/Incremental_build_model)
功能，可提升單一機器的建置效率。然而建置產物無法跨環境共享，迫使您在 [持續整合 (CI)
環境](https://en.wikipedia.org/wiki/Continuous_integration) 或本地開發環境（您的
Mac）中反覆重建相同程式碼。

Tuist 透過其快取功能解決這些挑戰，顯著縮短本地開發與 CI 環境的建置時間。此方法不僅加速反饋循環，更減少情境切換需求，最終提升生產力。

我們提供兩種快取類型：
- <LocalizedLink href="/guides/features/cache/module-cache">模組快取</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode
  快取</LocalizedLink>

## 模組快取{#module-cache}

針對採用 Tuist
<LocalizedLink href="/guides/features/projects">專案生成</LocalizedLink>功能的專案，我們提供強大的快取系統，能將個別模組以二進位形式快取，並在團隊與持續整合環境間共享。

雖然您亦可使用新版 Xcode
快取功能，但此功能目前針對本地建置進行優化，相較於生成專案快取，其命中率可能較低。然而，選擇何種快取方案取決於您的具體需求與偏好。您亦可結合兩種快取方案以達最佳成效。

<LocalizedLink href="/guides/features/cache/module-cache">深入了解模組快取
→</LocalizedLink>

## Xcode 快取{#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode 快取機制目前針對本地增量建置進行優化，且建置任務的完整流程尚未實現路徑獨立性。儘管如此，您仍可透過接入 Tuist
遠端快取獲得效益，隨著建置系統能力的持續提升，我們預期建置時間將逐步改善。
<!-- -->
:::

Apple 正在開發基於建置層級的新型快取解決方案，類似於 Bazel 和 Buck 等建置系統。此項新快取功能自 Xcode 26 起已開放使用，Tuist
現已與其無縫整合——無論您是否使用 Tuist 的
<LocalizedLink href="/guides/features/projects">專案生成</LocalizedLink>功能皆可適用。

<LocalizedLink href="/guides/features/cache/xcode-cache">深入了解 Xcode 快取
→</LocalizedLink>
