---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# 洞察合集{#bundle-size}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

随着应用功能的增加，应用包体积持续增长。虽然随着代码和资源的增加，包体积的增长在所难免，但仍有许多方法可以最小化这种增长，例如确保资源在包中不重复，或移除未使用的二进制符号。Tuist
为您提供工具和洞察力，帮助您的应用保持小巧体积——我们还会持续监控您的应用体积变化。

## 用法 {#usage｝

要分析代码包，可使用`tuist inspect bundle` 命令：

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

`tuist inspect bundle` 命令会分析该包，并提供链接供您查看包的详细概览，包括包内容扫描或模块分解：

![已分析的捆绑包](/images/guides/features/bundle-size/analyzed-bundle.png)

## 持续集成{#continuous-integration}

要追踪捆绑包随时间的变化，您需要在持续集成环境中分析该捆绑包。首先，需确保您的持续集成环境已完成<LocalizedLink href="/guides/integrations/continuous-integration#authentication">身份验证</LocalizedLink>：

GitHub Actions 的示例工作流如下所示：

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

配置完成后，您将能实时查看软件包体积随时间的变化趋势：

![Bundle size graph](/images/guides/features/bundle-size/bundle-size-graph.png)

## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要获取自动拉取/合并请求评论，请将您的<LocalizedLink href="/guides/server/accounts-and-projects">Tuist项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git平台</LocalizedLink>集成。
<!-- -->
:::

当您的Tuist项目与Git平台（如[GitHub](https://github.com)）关联后，每次执行`tuist inspect bundle`
时，Tuist将直接在您的拉取/合并请求中发布评论：![GitHub应用程序对检查包的评论](/images/guides/features/bundle-size/github-app-with-bundles.png)
