---
{
  "title": "Struo ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Struo の実行をライブ追跡し、アクション、所要時間、失敗、キャッシュの判断を確認します。"
}
---
# Struo のビルドインサイト {#struo-build-insights}

<a id="once-build-insights"></a>

Struo は実行中にランを Tuist にストリーミングするため、最終的な CI ログを待たずに進捗を確認できます。ランの開始時に出力されるダッシュボードのリンクを開き、グラフ、アクションのステータス、キャッシュの判定を確認してください。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo を使い始める</.localized_link> を完了し、Struo を実行するマシンを認証してください。

## ビルドを報告する {#report-your-builds}

Struo コマンドは引き続き使用できます。

```bash
struo build MyApplication
```

ライブレポートはベストエフォートです。レポートのエンドポイントが利用できない場合やセッションが期限切れの場合でも、ビルドは失敗しません。セッションが期限切れになった場合は、`struo auth login --provider tuist` で再度サインインしてください。

## ダッシュボードに表示される内容 {#what-the-dashboard-shows}

**Builds** と **Build Runs** を使用して、時間、ブランチ、ローカル環境または CI 環境にわたるランを比較します。各ランには次の情報が含まれる場合があります。

- リクエストされたコマンド、ステータス、開始時刻、および所要時間。
- Struo のバージョンと報告されたホスト情報。
- アクションとその依存関係、ステータス、所要時間、およびキャッシュの結果。
- 報告されたアクションエラー。
- クライアントによって報告された場合の Git ブランチ、コミット、および CI コンテキスト。

アクションを検索およびフィルタリングして、失敗した処理や遅い処理を見つけます。報告されたアクション名とソースファイルにより、作業をコードに結び付けることができます。古いクライアントでは詳細が少ない場合があります。キャッシュ済みまたはスキップされたアクションは実行された作業ではなく、タイミング情報が欠落していることは所要時間がゼロの実行ではありません。

Tuist は現在、Struo の生のアクションログストリームを取り込んでいません。プロセスの完全な出力を得るために CI ログを保持してください。ランの概要や構造化されたエラーは、それらのログの代わりにはなりません。

**Cache** ビューは、アクションの判定とコンテンツオブジェクトの転送を区別します。キャッシュアクティビティの解釈については、<.localized_link href="/guides/features/cache/struo">Struo キャッシュ</.localized_link> を参照してください。

## テスト {#tests}

テストコマンドも Struo ランを生成します。報告されたスイートとケースは **Tests** に表示され、ホストされたシャードはさらに統合されたテスト実行を公開します。<.localized_link href="/guides/features/test-insights/struo">Struo テストインサイト</.localized_link> を参照してください。

## コーディングエージェントと Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol ツール</.localized_link> を使用すると、エージェントが Struo ランを一覧表示し、ランのアクション合計とキャッシュ合計を読み取れます。同じ読み取りは HTTP API からも利用可能です。

確定した Struo のビルド健全性メトリクスには、<.localized_link href="/guides/integrations/grafana">Grafana 統合</.localized_link> を使用してください。Struo は現在、経過したキャッシュ時間の節約を報告しないため、その測定値はゼロではなく利用不可となります。
