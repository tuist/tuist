---
{
  "title": "代码覆盖率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追踪每次测试运行中每个文件和每行代码的覆盖率。"
}
---
# 代码覆盖率 {#code-coverage}

代码覆盖率会告诉你测试执行了代码中的哪些行。Tuist 会上传每次测试运行的覆盖率数据，并将一次提交中的所有运行结果合并为一个数值（按文件和整个项目分别统计），以便你在仪表盘中逐次提交跟踪该指标。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上传通过 tuist xcodebuild test 测试的 Xcode 项目的代码覆盖率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成的项目"
    details="使用 tuist test、二进制缓存和选择性测试来衡量 Tuist 生成项目中的代码覆盖率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上传通过 mix test --cover 测试的 Elixir 项目的行覆盖率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上传通过 cargo test 测试的 Rust 项目的行覆盖率。"
    link="/guides/features/test-code-coverage/rust"
/>
</.home_cards>
