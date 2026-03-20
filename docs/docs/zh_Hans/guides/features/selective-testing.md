---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 选择性测试{#selective-testing}

随着项目的扩展，测试数量也会随之增加。很长一段时间以来，在每次提交拉取请求（PR）或向`main`
推送代码时，运行所有测试都需要数十秒。但这种方案无法适应团队可能拥有的数千个测试。

在 CI 上的每次测试运行中，无论更改内容如何，您通常都会重新运行所有测试。Tuist 的选择性测试功能基于我们的
<LocalizedLink href="/guides/features/projects/hashing">哈希算法</LocalizedLink>，仅运行自上次成功测试运行以来发生更改的测试，从而帮助您大幅加快测试运行速度。

要使用<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>选择性运行测试，请执行`tuist
test`
命令。该命令会像处理<LocalizedLink href="/guides/features/cache/module-cache">模块缓存</LocalizedLink>那样对Xcode项目进行<LocalizedLink href="/guides/features/projects/hashing">哈希处理</LocalizedLink>，成功后将持久化哈希值，以便在后续运行中判断变更内容。
后续运行时，`tuist test` 将透明地使用这些哈希值筛选测试，仅执行自上次成功测试以来发生变更的测试项。

`tuist test` 直接集成
<LocalizedLink href="/guides/features/cache/module-cache">模块缓存</LocalizedLink>，利用本地或远程存储中的二进制文件，显著缩短测试套件的构建时间。选择性测试与模块缓存的结合，能大幅减少持续集成环境中的测试运行时长。

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
由于无法检测测试与源代码之间的代码内依赖关系，选择性测试的最大粒度为目标级别。因此，我们建议将目标保持得小而专注，以最大限度地发挥选择性测试的优势。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
测试覆盖率工具默认整个测试套件会一次性运行，这使得它们与选择性测试运行不兼容——这意味着在使用测试选择功能时，覆盖率数据可能无法真实反映实际情况。这是已知的局限性，并不意味着您做错了什么。
我们建议团队思考在此情境下覆盖率是否仍能提供有意义的洞察；若确实如此，请放心，我们正在研究如何在未来让覆盖率与选择性运行正常配合。
<!-- -->
:::


## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要获取自动拉取/合并请求评论，请将您的<LocalizedLink href="/guides/server/accounts-and-projects">Tuist项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git平台</LocalizedLink>集成。
<!-- -->
:::

当您的Tuist项目与Git平台（如[GitHub](https://github.com)）连接后，若在持续集成流程中使用`tuist test`
命令，Tuist将直接在拉取请求/合并请求中添加评论，包含已运行测试与跳过测试的详情：![GitHub应用评论含Tuist预览链接](/images/guides/features/selective-testing/github-app-comment.png)
