---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 整合{#github}

Git 倉庫是大多數軟體專案的核心。我們與 GitHub 整合，直接在您的拉取請求中提供 Tuist 的深入分析，並為您省下一些設定，例如同步預設分支。

## 設定{#setup}

您需要在組織的`Integrations` 標籤中安裝 Tuist GitHub 應用程式：
![顯示整合標籤的圖片](/images/guides/integrations/gitforge/github/integrations.png)。

之後，您就可以在 GitHub 倉庫和 Tuist 專案之間新增專案連線：

![顯示新增專案連線的影像](/images/guides/integrations/gitforge/github/add-project-connection.png)。

## 拉取/合併請求註解{#pull-merge-request-comments}

GitHub 應用程式會發佈 Tuist 執行報告，其中包含 PR 的摘要，包括最新
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>
或
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>
的連結：

![顯示 pull request
註解的圖片](/images/guides/integrations/gitforge/github/pull-request-comment.png)。

::: info REQUIREMENTS
<!-- -->
只有當您的 CI 執行為
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>
時，才會張貼註解。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
如果您的自訂工作流程不是由 PR commit 觸發，而是例如由 GitHub 的註解觸發，您可能需要確保`GITHUB_REF`
變數設定為`refs/pull/<pr_number>/merge` 或`refs/pull/<pr_number>/head`
。</pr_number></pr_number>

您可以執行相關指令，例如`tuist share` ，前綴為`GITHUB_REF`
環境變數：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head"
tuist share</code>
<!-- -->
:::
