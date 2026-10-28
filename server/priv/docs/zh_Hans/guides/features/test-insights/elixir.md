---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir 测试洞察 {#elixir-test-insights}

Tuist 的 Hex 包会在每次测试运行后上传你的 Elixir 项目的测试结果，让你直接在 Tuist 仪表盘中查看测试性能和不稳定测试。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">Elixir 入门</.localized_link>

## 报告你的测试运行 {#report-your-test-runs}

共享设置会安装测试集成。继续使用 `mix test`，参数、输出和退出代码保持不变：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 会在运行结束时报告结果；无需额外的测试别名。

你可以在 Tuist 仪表盘中访问测试洞察，并查看其随时间的变化：

![Phoenix 应用的测试仪表盘](/images/guides/features/elixir/tests-dashboard.png)

## 跟踪内容 {#what-is-tracked}

该包收集来自 ExUnit 的结果，包括：
- 单个测试的通过/失败状态和持续时间
- 每个测试所属的模块和 `describe` 块
- 每次失败的消息和位置
- 跨运行的不稳定测试检测
- 分支和提交，以及在持续集成中的提供者和运行
- 在持续集成中，检出仓库的 [Git 历史](#git-history)

文档测试与其他测试一样被报告。使用 `--cover` 时，还会上传运行的行覆盖率：请参阅 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代码覆盖率</.localized_link>。

> [!NOTE]
> 该包通过一个它添加到你已使用的格式化器旁边的 ExUnit 格式化器进行报告。如果你在命令行上传递 `--formatter`，Mix 会替换整个列表，因此不会报告运行，任务会对此发出警告。

### Git 历史 {#git-history}

在持续集成中，该包还会上传检出仓库的提交历史：提交 SHA、其父提交、提交日期，以及运行及其拉取请求的基础分支所在的分支。不会上传文件内容、提交消息或作者信息。这能让 Tuist 知道哪些提交合并到了你的默认分支，例如合并队列测试过的提交。该包读取检出仓库已有的历史，当检出仓库没有基础分支时，它会向远程询问最新的提交（`git ls-remote`）。在代码覆盖率（`--cover`）之外，它不会获取历史。

| 变量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不读取或上传任何 Git 历史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 仅读取检出仓库，不与远程联系。 |

## 故障排除 {#troubleshooting}

报告永远不会改变你的测试结果：如果无法发送报告，运行将按原样退出且不打印任何内容。要查看报告未发送的原因，请设置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
