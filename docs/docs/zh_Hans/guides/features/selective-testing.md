---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 选择性测试{#selective-testing}

随着项目规模扩大，测试用例数量也会增长。长期以来，在每个PR或推送至`主分支` 时运行全部测试需耗费数十秒。但该方案无法适应团队可能拥有的数千个测试用例。

在持续集成环境的每次测试运行中，您很可能无论变更与否都会重新运行所有测试。Tuist的自适应测试机制通过基于<LocalizedLink href="/guides/features/projects/hashing">哈希算法</LocalizedLink>，仅运行自上次成功测试后发生变更的测试项，可大幅提升测试执行效率。

选择性测试支持通过`xcodebuild` 命令运行，该命令兼容所有Xcode项目；若使用Tuist生成项目，可改用`tuist test`
命令，该命令提供额外便利功能（如与<LocalizedLink href="/guides/features/cache">二进制缓存</LocalizedLink>集成）。开始使用选择性测试时，请根据项目配置选择对应操作指南：

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated
  project</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
由于无法检测测试与源代码间的内部依赖关系，选择性测试的最大粒度仅能达到目标级别。因此建议保持目标小而聚焦，以充分发挥选择性测试的优势。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
测试覆盖率工具默认整个测试套件一次性运行，这使其与选择性测试运行不兼容——意味着在使用测试选择时，覆盖率数据可能无法真实反映实际情况。这是已知的限制，并不代表操作有误。
我们建议团队审视覆盖率在此场景下是否仍能提供有效洞察。若仍具价值，请放心——我们已着手研究如何使覆盖率在未来与选择性运行模式协同工作。
<!-- -->
:::


## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要获取自动拉取/合并请求评论，请将您的<LocalizedLink href="/guides/server/accounts-and-projects">Tuist项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git平台</LocalizedLink>集成。
<!-- -->
:::

当您的Tuist项目与Git平台（如[GitHub](https://github.com)）连接后，若在CI工作流中使用`tuist xcodebuild
test` 或`tuist test`
，Tuist将直接在您的拉取/合并请求中添加评论，包含已运行和跳过的测试项目：![GitHub应用评论中的Tuist预览链接](/images/guides/features/selective-testing/github-app-comment.png)
