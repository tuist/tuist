---
{
  "title": "Struo ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Struo の実行をリアルタイムに追跡し、アクション、所要時間、失敗、キャッシュの判断を検証します。"
}
---
# Struo ビルドインサイト {#struo-build-insights}

<a id="once-build-insights"></a>

Struo は実行中に Tuist へランをストリーミングするため、最終的な CI ログを待たずに進捗を確認できます。ランの開始時に出力されるダッシュボードのリンクを開き、グラフ、アクションの状態、キャッシュの判定を確認してください。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo の利用を開始する</.localized_link> を完了し、Struo を実行するマシンを認証してください。

## ビルドをレポートする {#report-your-builds}

Struo コマンドを引き続き使用してください:

```bash
struo build MyApplication
```

ライブレポートはベストエフォートです。レポート用エンドポイントが利用できない場合やセッションの有効期限が切れていても、ビルドは失敗しません。セッションの有効期限が切れた場合は、`struo auth login --provider tuist` で再度サインインしてください。

## ダッシュボードに表示される情報 {#what-the-dashboard-shows}

**Builds** と **Build Runs** を使用して、時間、ブランチ、ローカル環境または CI 環境にわたるランを比較します。各ランには次の情報が含まれます:

- リクエストされたコマンド、ステータス、開始時刻、および所要時間。
- Struo のバージョンと報告されたホスト情報。
- アクションとその依存関係、ステータス、所要時間、およびキャッシュ結果。
- 報告されたアクションのエラー。
- クライアントによって報告された場合の Git ブランチ、コミット、および CI コンテキスト。

アクションを検索・フィルタリングして、失敗した処理や低速な処理を見つけます。報告されたアクション名とソースファイルにより、作業をコードに紐付けることができます。古いクライアントでは詳細が少なくなる場合があります。キャッシュ済みまたはスキップされたアクションは実行された作業ではなく、タイミング情報の欠落は所要時間がゼロの実行を意味しません。

Tuist は現在、Struo の生アクションログストリームを取り込んでいません。完全なプロセス出力を得るために CI ログを保持してください。ランのサマリーや構造化されたエラーは、それらのログの代わりにはなりません。

**Cache** ビューは、アクションの判定とコンテンツオブジェクトの転送を分離して表示します。キャッシュ動作の解釈については <.localized_link href="/guides/features/cache/struo">Struo キャッシュ</.localized_link> を参照してください。

## テスト {#tests}

テストコマンドも Struo ランを生成します。報告されたスイートとケースは **Tests** に表示され、ホスト型シャードは統合されたテスト実行も公開します。<.localized_link href="/guides/features/test-insights/struo">Struo テストインサイト</.localized_link> を参照してください。

## コーディングエージェントと Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol ツール</.localized_link> により、エージェントは Struo ラン一覧を取得し、ランのアクション合計とキャッシュ合計を読み取ることができます。同じ読み取りは HTTP API からも利用可能です。

確定済みの Struo ビルド健全性メトリクスには <.localized_link href="/guides/integrations/grafana">Grafana 統合</.localized_link> を使用してください。Struo は現在、経過したキャッシュ時間の節約分を報告しないため、その測定値はゼロではなく利用不可として扱われます。
