---
{
  "title": "Once テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist で Once のテストバッチを計画し、CI ワーカーに分散して実行し、統合されたテスト実行を検証します。"
}
---
# Once テストシャーディング {#once-test-sharding}

テストスイートが単一のマシンでは処理しきれなくなった場合、Once は Tuist に検出されたテストバッチを CI ワーカーに分散するよう指示できます。ワーカーは Once を介して割り当てられたタスクを実行し、Tuist はそれらのレポートを 1 つのテスト実行に統合します。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/once-project">Once の利用を開始する</.localized_link>を完了してください。
> - `once query test-plan --shards` と `once test --shard-plan` を公開している Once リリースを使用してください。Once 0.71.0 はポータブルプランのみをサポートしており、このホスト型ワークフローはサポートしていません。
> - 選択したテストターゲットに対して完全な検出が行われていること、およびワーカー上で同じチェックアウトとテスト環境が利用可能であることを確認してください。

Tuist CLI のラッパーは不要です。Once はネイティブの Tuist プロバイダーと認証情報を使用します。

## テストを検出する {#discover-your-tests}

プランニングの前に検出を確立するため、選択したテストを実行してください。

```bash
once test MyTests --format json
```

利用可能なバッチの粒度はランナーによって異なります。ファイル単位またはケース単位のバッチをサポートするテストターゲットもあれば、ターゲットレベルのままのものもあります。検出とバッチ機能の詳細については、[Once のテスティングガイド](https://buildonce.dev/docs/guide/graph/testing)に従ってください。

## ホスト型プランを作成する {#create-a-hosted-plan}

プランニングジョブでは、この CI 実行で共有される参照を使用してください。

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

レスポンスには、ホスト型プラン ID と実際のワーカーインデックスが含まれます。

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI マトリクスは `shards` から構築し、4 つのエントリが含まれていると想定しないでください。空のプランは空の ID と配列を返すため、ワーカーを起動する必要はありません。プランを絞り込むには `--target` を渡し、Once のグラフベースの選択を使用するには `--changed-path` を繰り返してください。

参照はデフォルトで `TUIST_SHARD_REFERENCE` または検出された CI 実行になります。環境にサポートされている CI 識別子がない場合は、明示的に渡してください。

## 各シャードを実行する {#execute-each-shard}

各ワーカーに返されたプラン ID と独自のインデックスを指定してください。

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

あるいは、`TUIST_SHARD_PLAN_ID` と `TUIST_SHARD_INDEX` を設定してください。ワーカーは正確な UUID に紐づいたプランをダウンロードし、割り当てられたバッチのみを実行します。割り当てが空の場合、何も実行されません。結果の欠落、プロセスの失敗、中断された作業はパーティションを通過できません。

これはテストプランを分散するものであり、事前コンパイルされたテストビルドアーカイブではありません。ワーカー上で必要なソース、ツール、検出を準備してください。共有キャッシュを使用することで、対象となるビルド作業の繰り返しを回避できます。

## 再実行と結果 {#reruns-and-results}

再実行の場合は、`--shard-attempt` を増やすか、`TUIST_SHARD_ATTEMPT` を設定してください。それ以外の場合、Once は GitHub の実行試行回数を使用し、デフォルトは 1 です。`--shard-report-revision` のデフォルトは 0 で、同じ試行内でレポートを修正する際に増やすことができます。これらのカウンターはテストの再試行とは別ものです。

**Tests → Shards** を開いてプラン、バランス、報告されたワーカーを確認し、その後、個別の結果を確認するために結合されたテスト実行を開いてください。Once のスケジューリング単位は **Batches** とラベル付けされています。ケースはネイティブのターゲット、スイート、テスト名を保持します。

レポートの詳細とカバレッジの制限については、<.localized_link href="/guides/features/test-insights/once">Once テストインサイト</.localized_link>を参照してください。
