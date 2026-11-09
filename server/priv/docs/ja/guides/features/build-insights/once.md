---
{
  "title": "Once ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Once の実行をリアルタイムに追跡し、アクション、所要時間、失敗、キャッシュの判定を確認します。"
}
---
# Once ビルドインサイト {#once-build-insights}

Once は実行中に Tuist へランをストリーミングするため、最終的な CI ログを待たずに進捗を確認できます。ラン開始時に出力されるダッシュボードのリンクを開き、グラフ、アクションの状態、キャッシュの判定を確認してください。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/once-project">Once のはじめ方</.localized_link> を完了し、Once を実行するマシンで認証を行ってください。

## ビルドをレポートする {#report-your-builds}

Once コマンドは引き続き使用できます。

```bash
once build MyApplication
```

ライブレポートはベストエフォートです。レポートエンドポイントが利用できない場合やセッションが期限切れの場合でも、ビルドは失敗しません。セッションが期限切れになった場合は、`once auth login --provider tuist` で再度サインインしてください。

## ダッシュボードに表示される内容 {#what-the-dashboard-shows}

**Builds** と **Build Runs** を使用して、時間、ブランチ、ローカル環境または CI 環境にわたるランを比較できます。各ランには以下の情報が含まれます。

- リクエストされたコマンド、ステータス、開始時刻、および所要時間。
- Once のバージョンと報告されたホスト情報。
- アクションとその依存関係、ステータス、所要時間、およびキャッシュの結果。
- 報告されたアクションのエラー。
- クライアントによって報告された場合の Git ブランチ、コミット、および CI コンテキスト。

アクションを検索・フィルタリングして、失敗した処理や低速な処理を見つけます。報告されたアクション名とソースファイルにより、作業をコードに結びつけることができます。古いクライアントでは詳細が少なくなる場合があります。キャッシュ済みまたはスキップされたアクションは実行された作業ではなく、タイミング情報が欠落している場合でもゼロ時間の実行とはなりません。

Tuist は現在、Once の生のアクションログストリームを取り込んでいません。完全なプロセス出力については CI ログを保持してください。ランの概要や構造化されたエラーは、それらのログの代わりにはなりません。

**Cache** ビューでは、アクションの判定とコンテンツオブジェクトの転送を区別します。キャッシュ活動の解釈については <.localized_link href="/guides/features/cache/once">Once キャッシュ</.localized_link> を参照してください。

## テスト {#tests}

テストコマンドも Once ランを生成します。報告されたスイートとケースは **Tests** に表示され、ホスト型シャードはさらに統合されたテスト実行を公開します。<.localized_link href="/guides/features/test-insights/once">Once テストインサイト</.localized_link> を参照してください。

## コーディングエージェントと Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol ツール</.localized_link> を使用すると、エージェントが Once ラン一覧を取得し、ランのアクション合計とキャッシュ合計を読み取れます。同じ読み取りは HTTP API 経由でも利用可能です。

確定済みの Once ビルド健全性メトリクスには <.localized_link href="/guides/integrations/grafana">Grafana 連携</.localized_link> を使用してください。Once は現在、キャッシュによる経過時間の短縮効果を報告しないため、その測定値はゼロではなく利用不可として扱われます。
