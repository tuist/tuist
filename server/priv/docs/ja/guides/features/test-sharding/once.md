---
{
  "title": "Once テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist で Once のテストバッチを計画し、CI ワーカーに分散して実行し、統合されたテスト実行結果を確認します。"
}
---
# Once テストシャーディング {#once-test-sharding}

テストスイートが単一のマシンで処理しきれなくなった場合、Once は Tuist に発見されたテストバッチを CI ワーカーに分散させるよう依頼できます。各ワーカーは Once を介して割り当てられたタスクを実行し、Tuist がそれらのレポートを 1 つのテスト実行に統合します。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/once-project">Once の使い始め</.localized_link>を完了してください。
> - `once query test-plan --shards` と `once test --shard-plan` を公開している Once リリースを使用してください。Once 0.71.0 はポータブルプランのみをサポートしており、このホスト型ワークフローはサポートしていません。
> - 選択したテストターゲットに対する完全なディスカバリーを行い、ワーカー上で同じチェックアウトとテスト環境を利用できるようにしてください。

Tuist CLI のラッパーは不要です。Once はネイティブの Tuist プロバイダーと認証情報を使用します。

## テストのディスカバリー {#discover-your-tests}

プランニング前にディスカバリーを確立するため、選択したテストを実行してください：

```bash
once test MyTests --format json
```

利用可能なバッチの粒度はランナーによって異なります。ファイル単位やケース単位のバッチに対応するテストターゲットもあれば、ターゲットレベルのままのものもあります。ディスカバリーとバッチ機能の詳細については、[Once のテスティングガイド](https://buildonce.dev/docs/guide/graph/testing)を参照してください。

## ホスト型プランの作成 {#create-a-hosted-plan}

プランニングジョブでは、この CI 実行で共有されるリファレンスを使用してください：

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

レスポンスにはホスト型プラン ID と実際のワーカーインデックスが含まれます：

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI マトリクスは `shards` から構築し、4 つのエントリがあると想定しないでください。空のプランは空の ID と配列を返すため、ワーカーを起動する必要はありません。プランを絞り込むには `--target` を渡し、Once のグラフベースの選択を使用するには `--changed-path` を繰り返し指定してください。

リファレンスのデフォルト値は `TUIST_SHARD_REFERENCE` または検出された CI 実行です。環境にサポートされている CI 識別子がない場合は、明示的に渡してください。

## 各シャードの実行 {#execute-each-shard}

各ワーカーに返されたプラン ID と自身のインデックスを指定してください：

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

あるいは、`TUIST_SHARD_PLAN_ID` と `TUIST_SHARD_INDEX` を設定することもできます。ワーカーは正確な UUID に紐づけられたプランをダウンロードし、割り当てられたバッチのみを実行します。割り当てが空の場合は何も実行されません。結果の欠落、プロセスの失敗、中断された作業はパーティションを通過できません。

これはテストプランを分散するものであり、事前コンパイルされたテストビルドアーカイブではありません。ワーカー上で必要なソース、ツール、およびディスカバリーを準備してください。共有キャッシュを活用することで、対象となるビルド作業の繰り返しを回避できます。

## 再実行と結果 {#reruns-and-results}

再実行の場合は `--shard-attempt` を増やすか、`TUIST_SHARD_ATTEMPT` を設定してください。それ以外の場合、Once は GitHub の実行アテンプトを使用し、デフォルトは 1 です。`--shard-report-revision` のデフォルトは 0 で、同じアテンプト内でレポートを修正する際に増やすことができます。これらのカウンターはテストの再試行とは別物です。

**Tests → Shards** を開いてプラン、バランス、報告されたワーカーを確認し、その後結合されたテスト実行を開いて個別の結果を確認してください。Once のスケジューリング単位は **Batches** とラベル付けされます。ケースはネイティブのターゲット、スイート、およびテスト名を保持します。

レポートの詳細とカバレッジの制限については、<.localized_link href="/guides/features/test-insights/once">Once テストインサイト</.localized_link>を参照してください。
