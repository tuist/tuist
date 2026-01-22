---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# 整合洞察{#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

隨著應用程式新增更多功能，您的應用程式封裝大小持續增長。雖然隨著更多程式碼與資源的發布，封裝大小的增長在所難免，但仍有諸多方法可減緩此增長趨勢，例如確保資源在不同封裝間不重複存在，或移除未使用的二進位符號。Tuist
提供工具與分析洞察，協助您維持應用程式體積精簡——我們更會持續監測您的應用程式大小變化。

## 用法{#usage}

要分析程式碼包，可使用以下指令：`tuist inspect bundle`

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

執行 ``tuist inspect bundle` ` 指令可分析套件，並提供連結供您檢視套件詳細概覽，包含套件內容掃描或模組分解資訊：

![已分析的組合](/images/guides/features/bundle-size/analyzed-bundle.png)

## 持續整合{#continuous-integration}

為追蹤隨時間變化的套件大小，您需在持續整合環境中分析該套件。首先，請確保您的持續整合環境已完成<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>：

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

設定完成後，您將能觀察到您的套件大小隨時間演變的趨勢：

![封裝大小圖表](/images/guides/features/bundle-size/bundle-size-graph.png)

## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>整合。
<!-- -->
:::

當您的 Tuist 專案與 Git 平台（如 [GitHub](https://github.com)）完成串接後，每當執行`tuist inspect
bundle` 時，Tuist 將直接在您的拉取/合併請求中發布評論：![GitHub app comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
