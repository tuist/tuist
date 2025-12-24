---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHubとの統合{#github}

Gitリポジトリは、世の中の大半のソフトウェアプロジェクトの中心的存在です。私たちはGitHubと統合し、プルリクエストでTuistの洞察を提供したり、デフォルトブランチの同期などの設定を省くことができます。

## セットアップ{#setup}

組織の`Integrations` タブに Tuist GitHub アプリをインストールする必要があります:
![integrationsタブを示す画像](/images/guides/integrations/gitforge/github/integrations.png)。

その後、GitHubリポジトリとTuistプロジェクトの間にプロジェクト接続を追加できます：

プロジェクト接続を追加するイメージ](/images/guides/integrations/gitforge/github/add-project-connection.png)。

## プル/マージリクエストのコメント{#pull-merge-request-comments}

GitHubアプリは、最新の<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>や<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>へのリンクを含むPRの要約を含むTuist実行レポートを投稿します：

プルリクエストのコメントを表示する画像](/images/guides/integrations/gitforge/github/pull-request-comment.png)。

::: info REQUIREMENTS
<!-- -->
コメントが投稿されるのは、CIの実行が<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証</LocalizedLink>された場合のみです。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
PR のコミットではなく GitHub のコメントなどをトリガーとするカスタムワークフローの場合は、`GITHUB_REF`
変数に`refs/pull/<pr_number>/merge` または`refs/pull/<pr_number>/head`
のいずれかを設定する必要があります。</pr_number></pr_number>

`tuist share` のように、`GITHUB_REF`
環境変数を前に付けて、関連するコマンドを実行できます：<code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
