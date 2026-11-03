---
locale: zh_Hant
glossary:
  tests: 測試
  features: 功能
  cache hit: 快取命中
  cache miss: 快取未命中
  flaky tests: 不穩定測試
  test run: 測試執行
  test case: 測試案例
  selective testing: 選擇性測試
---

## Traditional Chinese-specific translation rules

## Voice and Typography

- Write natural Traditional Chinese for developers. This locale uses standard written Chinese, not the Cantonese voice of `yue_Hant`. Use "你" when direct address is needed, but usually omit unnecessary pronouns and possessives.
- Omit final "。" or ASCII periods in headings, navigation, buttons, and short feature labels. Keep normal Chinese sentence punctuation in descriptions and paragraphs. Do not insert spaces between Chinese words or imitate English title case.
- Use consistent Traditional Chinese developer vocabulary: "軟體", "專案", "建置", "快取", "執行", and "回饋". Do not merely convert Simplified characters while retaining a different regional glossary, or alternate "建置" with "構建" for the same concept.

## Developer Vocabulary and Marketing

- Use "相依性解析" for dependency resolution and "不穩定測試" or "間歇性失敗的測試" for flaky tests. Distinguish the build process, build artifact, and build count from their context rather than using one expanded label everywhere.
- "Shipping" means "交付軟體" or "發布更新", not "出貨" or "運送". Prefer familiar local technical vocabulary over unexplained English loanwords.
- For "Less waiting. More shipping.", a natural direction is "減少等待，專注開發". For "More in the toolbox", prefer "更多工具，協助團隊開發" to a literal toolbox metaphor.
- A newsletter issue is a "期", not a "問題". Keep cached reuse distinct from failed execution, and preserve the difference between a test that still executes with ignored failures and one that does not execute.
