---
{
  "title": "Elixir 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Elixir 项目的测试，以监控测试性能。"
}
---
# Elixir 测试洞察 {#elixir-test-insights}

Tuist 的 Hex 包会在每次测试运行后上传你的 Elixir 项目的测试结果，让你在 Tuist 仪表盘中直接查看测试性能和不稳定测试。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">Elixir 入门</.localized_link>

## 上报你的测试运行 {#report-your-test-runs}

共享设置会安装测试集成。继续使用 `mix test`，参数、输出和退出码保持不变：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 会在运行结束时上报；无需额外的测试别名。

你可以在 Tuist 仪表盘中访问测试洞察，并查看其随时间的变化：

![Phoenix 应用的测试仪表盘](/images/guides/features/elixir/tests-dashboard.png)

## 追踪内容 {#what-is-tracked}

该包会收集 ExUnit 的结果，包括：
- 每个测试的通过/失败状态和耗时
- 每个测试所属的模块和 `describe` 块
- 每次失败的消息和位置
- 跨运行的不稳定测试检测
- 分支和提交，以及在持续集成中的提供者和运行
- 在持续集成中，检出仓库的 [Git 历史](#git-history)

文档测试会像其他测试一样被上报。使用 `--cover` 时，还会上传运行的行覆盖率：参见 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代码覆盖率</.localized_link>。

> [!NOTE]
> 该包通过一个 ExUnit 格式化器进行上报，它会与你已使用的格式化器并列添加。如果你在命令行中传入 `--formatter`，Mix 会替换整个列表，因此不会上报该运行，任务会对此发出警告。

### Git 历史 {#git-history}

在持续集成中，该包还会上传检出仓库的提交历史：提交 SHA、其父提交、提交日期，以及运行及其拉取请求的基础分支所在的分支。不会上传文件内容、提交消息或作者信息。这能让 Tuist 知道哪些提交合并到了你的默认分支，例如合并队列测试过的提交。该包会读取检出仓库已有的历史；当检出仓库不包含基础分支时，它会向远程询问最新提交（`git ls-remote`）。除代码覆盖率（`--cover`）外，它不会获取历史。

| 变量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不读取或上传任何 Git 历史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 仅读取检出仓库，不联系远程。 |

## 故障排查 {#troubleshooting}

上报不会改变测试结果：如果无法发送报告，运行会按原样退出且不打印任何内容。要查看报告未发送的原因，请设置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
