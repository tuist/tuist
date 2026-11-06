---
locale: zh_Hans
glossary:
  tests: 测试
  features: 功能
  cache hit: 缓存命中
  cache miss: 缓存未命中
  flaky tests: 不稳定测试
  test run: 测试运行
  test case: 测试用例
  selective testing: 选择性测试
---

## Simplified Chinese-specific translation rules

## Voice and Typography

- Write natural Simplified Chinese for developers, not translated English sentence patterns. Use "你" when direct address is needed, but omit unnecessary pronouns and possessives. Avoid stiff constructions such as repeated "让我们成为您的".
- Omit final "。" or ASCII periods in headings, navigation, buttons, and short feature labels. Keep normal Chinese sentence punctuation in descriptions and paragraphs. Do not insert spaces between Chinese words or imitate English title case.
- Use Simplified Chinese vocabulary consistently: "软件", "项目", "构建", "缓存", "运行", and "反馈". Do not mix in Traditional Chinese variants or regional terms such as "專案" and "快取".

## Developer Vocabulary and Marketing

- Use "依赖解析" for dependency resolution and "不稳定测试" or "间歇性失败的测试" for flaky tests. Distinguish "构建" from "构建次数": add "次数" only when the source actually labels a count.
- "Shipping" means "交付软件" or "发布更新", not "发货" or "运输". Prefer familiar local technical vocabulary over unexplained English loanwords.
- For "Less waiting. More shipping.", a natural direction is "减少等待，专注开发". For "More in the toolbox", prefer "更多工具，助力团队开发" to a literal reference to what is inside a toolbox.
- A newsletter issue is a "期", not a "问题". A test run, a test case, and each execution of that case are different measurements; preserve the unit and only add count wording where the source counts them.
