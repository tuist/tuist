---
{
  "title": "HTTPプロキシ",
  "titleTemplate": ":title | インテグレーション | ガイド | Tuist",
  "description": "HTTPS_PROXYまたはHTTP_PROXYが設定されている場合に、TuistがHTTPトラフィックを企業プロキシ経由でルーティングする方法を学びます。"
}
---
# HTTPプロキシ {#http-proxy}

環境変数で `HTTPS_PROXY` または `HTTP_PROXY` が設定されている場合、Tuist は管理する HTTP 接続をそのプロキシ経由で自動的にルーティングします。これは Tuist CLI と Tuist Gradle プラグインの両方に適用され、追加の設定は不要です。

この動作は `curl`、`git`、および多くの開発者向けツールで使用される慣習に準拠しているため、他のツール用にこれらの変数をすでに設定している環境であれば、Tuist もすぐに利用できます。

## プロキシ対象 {#what-is-proxied}

プロキシ経由でルーティングされるのは、Tuist が所有する HTTP クライアントのみです。

- キャッシュ、プレビュー、アナリティクス、レジストリのエンドポイント、
- Gradle プラグインが Tuist のサービス（リモートビルドキャッシュ、ビルドインサイト、テストインサイト、テスト検疫、テストシャーディング）に対して行う呼び出し。

## 変数の参照順序 {#variable-lookup-order}

Tuist は次の順序で最初に空でない値を読み取ります。

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

値は `http://proxy.corp:8080` のような URL でなければなりません。インライン認証情報（`http://user:password@proxy.corp:8080`）もサポートされます。
