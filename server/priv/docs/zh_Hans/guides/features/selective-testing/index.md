---
{
  "title": "选择性测试",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 选择性测试，仅运行受最新更改影响的测试，让持续集成在数秒内提供反馈。"
}
---
# 选择性测试 {#selective-testing}

随着项目规模扩大，在每次推送时运行所有测试已不再可行。Tuist 选择性测试通过仅运行自上次成功运行以来发生变更所影响的测试，大幅缩短测试时间，具体借助我们的 <.localized_link href="/guides/features/projects/hashing">哈希算法</.localized_link>。

## 支持的构建系统 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

计划支持其他构建系统。
