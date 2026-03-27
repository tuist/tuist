---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 集成{#github}

Git 仓库是绝大多数软件项目的核心。我们与 GitHub 集成，可直接在您的拉取请求中提供 Tuist 见解，并为您节省一些配置，如同步默认分支。

## 设置{#setup}

您需要在组织的`Integrations` 标签中安装 Tuist GitHub 应用程序：
![显示集成标签的图片](/images/guides/integrations/gitforge/github/integrations.png)。

然后，就可以在 GitHub 仓库和 Tuist 项目之间添加项目连接：

显示添加项目连接的图像](/images/guides/integrations/gitforge/github/add-project-connection.png)。

## 拉取/合并请求注释{#pull-merge-request-comments}

GitHub 应用程序会发布 Tuist 运行报告，其中包括 PR 的摘要，包括最新
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>
或
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>
的链接：

![显示拉取请求注释的图片](/images/guides/integrations/gitforge/github/pull-request-comment.png)!

::: info REQUIREMENTS
<!-- -->
只有当您的 CI 运行通过
<LocalizedLink href="/guides/integrations/continuous-integration#authentication"> 验证</LocalizedLink>时，才会发布注释。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
如果您的自定义工作流不是由 PR 提交触发，而是由 GitHub 评论触发，则可能需要确保`GITHUB_REF`
变量设置为`refs/pull/<pr_number>/merge` 或`refs/pull/<pr_number>/head`
。</pr_number></pr_number>

您可以运行相关命令，如`tuist share` ，前缀为`GITHUB_REF`
环境变量：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head"
tuist share</code>
<!-- -->
:::
