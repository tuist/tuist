---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 集成{#github}

Git 仓库是绝大多数软件项目的核心。我们与 GitHub 集成，可在您的拉取请求中直接提供 Tuist 洞察，并为您省去默认分支同步等配置工作。

## 设置{#setup}

您需要在组织设置的`集成选项卡中安装Tuist
GitHub应用：`![集成选项卡示意图](/images/guides/integrations/gitforge/github/integrations.png)

之后，您可以在 GitHub 仓库与 Tuist 项目之间建立项目关联：

![展示添加项目连接的示意图](/images/guides/integrations/gitforge/github/add-project-connection.png)

## 拉取/合并请求注释{#pullmerge-request-comments}

GitHub 应用会发布 Tuist 运行报告，其中包含 PR 摘要及最新
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">预览</LocalizedLink>
或
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">测试</LocalizedLink>
的链接：

![展示拉取请求评论的图片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
该评论仅在您的CI运行通过<LocalizedLink href="/guides/integrations/continuous-integration#authentication">身份验证</LocalizedLink>后才会发布。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
`
若您使用的是非基于PR提交触发的自定义工作流（例如基于GitHub评论），则需确保`的GITHUB_REF变量设置为：`refs/pull/<pr_number>/merge`
或`refs/pull/<pr_number>/head` 。</pr_number></pr_number>

可运行相关命令，例如：`tuist share` ，需预先设置环境变量：`GITHUB_REF`
：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist
share</code>
<!-- -->
:::
