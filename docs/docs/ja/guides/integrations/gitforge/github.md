---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHubの統合{#github}。

Gitリポジトリは、世の中の大半のソフトウェアプロジェクトの中心的存在です。私たちはGitHubと統合し、プルリクエストでTuistの洞察を提供したり、デフォルトブランチの同期などの設定を省くことができます。

## セットアップ {#setup}

Tuist
GitHubアプリ](https://github.com/marketplace/tuist)をインストールします。インストールしたら、TuistにリポジトリのURLを次のように伝える必要がある：

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
