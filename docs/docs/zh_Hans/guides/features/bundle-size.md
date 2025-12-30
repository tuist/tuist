---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# 捆绑见解{#bundle-size}

警告要求
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>
<!-- -->
:::

随着应用程序功能的增加，应用程序捆绑包的大小也在不断增长。虽然随着代码和资产的增加，捆绑包大小的增长是不可避免的，但有很多方法可以最大限度地减少这种增长，例如确保您的资产不会在捆绑包中重复，或删除未使用的二进制符号。Tuist
为您提供各种工具和洞察力，帮助您的应用程序保持较小的大小，而且我们还会随着时间的推移监控您的应用程序大小。

## 用法 {#usage｝

要分析捆绑包，可以使用`tuist inspect bundle` 命令：

代码组
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

`tuist inspect bundle` 命令会对软件包进行分析，并为您提供一个链接，以查看软件包的详细概览，包括软件包内容扫描或模块明细：

[分析捆绑](/images/guides/features/bundle-size/analyzed-bundle.png)。

## 持续集成{#continuous-integration}

要跟踪随时间变化的捆绑包大小，您需要分析 CI 上的捆绑包。首先，您需要确保您的 CI 经过
<LocalizedLink href="/guides/integrations/continuous-integration#authentication"> 验证</LocalizedLink>：

GitHub 操作的工作流程示例如下：

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

设置完成后，您就可以查看捆绑包大小随时间的变化情况：

![捆扎尺寸图](/images/guides/features/bundle-size/bundle-size-graph.png)!

## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要自动获取拉取/合并请求注释，请将<LocalizedLink href="/guides/server/accounts-and-projects">Tuist 项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>集成。
<!-- -->
:::

一旦 Tuist 项目与 [GitHub](https://github.com) 等 Git 平台连接，只要运行`tuist inspect bundle`:
![GitHub
应用程序注释与检查过的捆绑包](/images/guides/features/bundle-size/github-app-with-bundles.png)，Tuist
就会直接在拉取/合并请求中发布注释。
