---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 选择性测试{#selective-testing}

随着项目的发展，测试量也在增加。长期以来，在每个 PR 上运行所有测试或推送到`main`
都需要几十秒的时间。但这种解决方案无法扩展到团队可能拥有的数千个测试。

每次在 CI 上运行测试时，您很可能都要重新运行所有测试，而不管发生了什么变化。Tuist
的选择性测试基于我们的<LocalizedLink href="/guides/features/projects/hashing">哈希算法</LocalizedLink>，只运行上次成功运行测试后发生变化的测试，从而帮助您大大加快测试运行速度。

选择性测试可与`xcodebuild` 一起使用，它支持任何 Xcode 项目；如果使用 Tuist 生成项目，则可以使用`tuist test`
命令，它提供了一些额外的便利，例如与 <LocalizedLink href="/guides/features/cache"> 二进制缓存</LocalizedLink>的集成。要开始选择性测试，请根据您的项目设置遵循相关说明：

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated project</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
由于无法检测测试与源代码之间的代码内依赖关系，选择性测试的最大粒度是目标级别。因此，我们建议将目标保持在较小的范围内，并突出重点，以最大限度地发挥选择性测试的优势。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
测试覆盖率工具假定整个测试套件一次性运行，这使得它们与选择性测试运行不兼容--这意味着在使用测试选择时，覆盖率数据可能无法反映实际情况。这是众所周知的局限性，但这并不意味着你做错了什么。我们鼓励团队反思覆盖率在这种情况下是否仍能带来有意义的见解，如果是，请放心，我们已经在考虑如何让覆盖率在未来与选择性运行正常配合。
<!-- -->
:::


## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要自动获取拉取/合并请求注释，请将<LocalizedLink href="/guides/server/accounts-and-projects">Tuist 项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>集成。
<!-- -->
:::

一旦您的 Tuist 项目与 [GitHub](https://github.com) 等 Git 平台连接，并且您开始使用`tuist xcodebuild
test` 或`tuist test` 作为 CI 流程的一部分，Tuist 将直接在您的拉取/合并请求中发布注释，包括哪些测试已运行，哪些测试被跳过：
![带有 Tuist 预览链接的 GitHub
应用程序注释](/images/guides/features/selective-testing/github-app-comment.png)。
