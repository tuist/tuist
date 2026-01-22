---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub 統合{#github}

Gitリポジトリは、世の中のソフトウェアプロジェクトの大半において中核をなす存在です。私たちはGitHubと連携し、プルリクエスト内で直接Tuistのインサイトを提供するとともに、デフォルトブランチの同期といった設定作業を省きます。

## 設定{#setup}

組織の`の「統合」タブ（` ）でTuist
GitHubアプリをインストールする必要があります：![統合タブを表示する画像](/images/guides/integrations/gitforge/github/integrations.png)

その後、GitHubリポジトリとTuistプロジェクトの間にプロジェクト接続を追加できます：

![プロジェクト接続の追加を示す画像](/images/guides/integrations/gitforge/github/add-project-connection.png)

## プル/マージリクエストのコメント{#pullmerge-request-comments}

GitHubアプリはTuist実行レポートを投稿します。これにはPRの概要と、最新の<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">プレビュー</LocalizedLink>または<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">テスト</LocalizedLink>へのリンクが含まれます：

![プルリクエストのコメントを示す画像](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
コメントは、CIの実行が<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>の場合にのみ投稿されます。
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
プルリクエストのコミットではなく、例えばGitHubコメントでトリガーされるカスタムワークフローを使用している場合、`GITHUB_REF`
変数が以下のいずれかに設定されていることを確認する必要があります：`refs/pull/<pr_number>/merge`
または`refs/pull/<pr_number>/head`</pr_number></pr_number>

関連するコマンド（例：`tuist share` ）を、`GITHUB_REF`
環境変数を接頭辞として実行できます：<code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
