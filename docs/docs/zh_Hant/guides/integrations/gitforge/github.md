---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 整合{#github}

Git 儲存庫是絕大多數軟體專案的核心。我們與 GitHub 整合，讓您能在拉取請求中直接查看 Tuist 洞察，並省去同步預設分支等設定步驟。

## 設定{#setup}

您需在組織的「`整合」` 標籤頁中安裝 Tuist GitHub
應用程式：![顯示整合標籤頁的圖片](/images/guides/integrations/gitforge/github/integrations.png)

之後，您即可在 GitHub 儲存庫與 Tuist 專案之間建立專案連結：

![示意新增專案連結的圖片](/images/guides/integrations/gitforge/github/add-project-connection.png)

## 拉取/合併請求註解{#pullmerge-request-comments}

GitHub 應用程式會發佈 Tuist 執行報告，其中包含拉取請求摘要，並附上最新
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">預覽</LocalizedLink>
或
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">測試</LocalizedLink>
的連結：

![顯示拉取請求評論的圖片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
註解僅在您的 CI 執行完成
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>後才會發布。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
` 若您使用自訂工作流程，且該流程並非在拉取請求提交時觸發（例如針對 GitHub 評論），則需確保變數 ```
的 `GITHUB_REF` 參數設定為以下任一值：``refs/pull/<pr_number>/merge``` `或``refs/pull/<pr_number>/head````</pr_number></pr_number>

可執行相關指令，例如：`tuist share` ，並預先設定環境變數：`GITHUB_REF`
：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist
share</code>
<!-- -->
:::
