---
{
  "title": "選擇性測試",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，僅執行受最新變更影響的測試，讓持續整合在數秒內提供回饋。"
}
---
# 選擇性測試 {#selective-testing}

隨著專案規模擴大，每次推送都執行所有測試已不再可行。Tuist 選擇性測試能大幅縮短測試時間，只執行受上次成功執行以來變更影響的測試，並使用我們的 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

## 支援的建置系統 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

我們計畫支援其他建置系統。
