---
{
  "title": "選擇性測試",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，只執行受最新改動影響的測試，讓持續整合於數秒內提供反饋。"
}
---
# 選擇性測試{#selective-testing}

隨著項目規模擴大，每次推送都執行所有測試變得不可行。Tuist 選擇性測試利用我哋嘅<.localized_link href="/guides/features/projects/hashing">哈希演算法</.localized_link>，只運行受上次成功運行以來變更影響嘅測試，從而大幅縮短測試時間。

## 支援嘅構建系統{#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

我哋計劃支援其他構建系統。
