---
{
  "title": "HTTPプロキシ",
  "titleTemplate": ":title | インテグレーション | ガイド | Tuist",
  "description": "HTTPS_PROXYまたはHTTP_PROXYが設定されている場合に、TuistがHTTPトラフィックを企業プロキシ経由でルーティングする方法について学びます。"
}
---
# HTTPプロキシ {#http-proxy}

環境変数`HTTPS_PROXY`または`HTTP_PROXY`が設定されている場合、Tuistは管理するHTTP接続をそのプロキシ経由で自動的にルーティングします。これはTuist CLIとTuist Gradleプラグインの両方に適用され、追加の設定は不要です。

この動作は`curl`、`git`、およびほとんどの開発者ツールで使用される慣習に準拠しているため、他のツール用にこれらの変数をすでに設定している環境であれば、Tuistもそのまま利用できます。

## プロキシの対象 {#what-is-proxied}

プロキシ経由でルーティングされるのは、Tuistが所有するHTTPクライアントのみです。

- キャッシュ、プレビュー、アナリティクス、レジストリのエンドポイント、
- GradleプラグインからTuistサービス（リモートビルドキャッシュ、ビルドインサイト、テストインサイト、テスト検疫、テストシャーディング）への呼び出し。

## 変数の参照順序 {#variable-lookup-order}

Tuistは以下の順序で最初に空でない値を読み取ります。

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

値は`http://proxy.corp:8080`のようなURLである必要があります。インライン認証情報（`http://user:password@proxy.corp:8080`）も有効です。
