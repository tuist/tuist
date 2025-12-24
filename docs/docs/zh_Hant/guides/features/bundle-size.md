---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# 捆綁式洞察力{#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

當您在應用程式中加入更多功能時，您的應用程式 bundle 大小也會不斷增加。當您發送更多的程式碼和資產時，有些 bundle
大小的成長是不可避免的，但有許多方法可以將成長減至最低，例如確保您的資產不會在您的 bundle 中重複，或剝除未使用的二進位符號。Tuist
為您提供工具和洞察力，幫助您的應用程式大小保持在較小的範圍內 - 我們也會隨時間監控您的應用程式大小。

## 使用方式{#usage}

若要分析 bundle，您可以使用`tuist inspect bundle` 指令：

::: code-group
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

`tuist inspect bundle` 指令會分析 bundle，並提供連結讓您查看 bundle 的詳細概觀，包括掃描 bundle 的內容或模組明細：

![分析束](/images/guides/features/bundle-size/analyzed-bundle.png)

## 持續整合{#continuous-integration}

若要隨時間追蹤 bundle 大小，您需要分析 CI 上的 bundle。首先，您需要確保您的 CI 已經<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>：

GitHub Actions 的示例工作流程如下：

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

一旦設定好，您就可以看到您的捆綁大小是如何隨著時間演變的：

![Bundle size graph](/images/guides/features/bundle-size/bundle-size-graph.png)

## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git 平台</LocalizedLink>整合。
<!-- -->
:::

一旦您的 Tuist 專案與 [GitHub](https://github.com) 等 Git 平台連線，每當您執行 `tuist inspect bundle` 時，Tuist 會直接在您的 pull/merge request 中發佈註解：

![GitHub app comment with inspected bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
