---
{
  "title": "Struo テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist で Struo のテストバッチを計画し、CI ワーカーに分散して実行し、統合されたテスト実行結果を確認します。"
}
---
# Struo テストシャーディング {#struo-test-sharding}

<a id="once-test-sharding"></a>

テストスイートが単一のマシンでは処理しきれなくなった場合、Struo は Tuist に検出したテストバッチを CI ワーカーに分散させるよう指示できます。各ワーカーは Struo を介して割り当てられたタスクを実行し、Tuist がそれらのレポートを 1 つのテスト実行に統合します。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo の使い始め</.localized_link>を完了してください。
> - [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 以降を使用し、`struo query test-plan --shards` および `struo test --shard-plan` を利用できるようにしてください。
> - 選択したテストターゲットに対する完全なディスカバリーが行われており、ワーカー上で同じチェックアウトとテスト環境が利用可能であること。

Tuist CLI のラッパーは不要です。Struo はネイティブの Tuist プロバイダーと認証情報を使用します。

## テストをディスカバーする {#discover-your-tests}

プランニングの前にディスカバリーを確立するため、選択したテストを実行します。

```bash
struo test MyTests --format json
```

利用可能なバッチの粒度はランナーによって異なります。ファイル単位やケース単位のバッチをサポートするテストターゲットもありますが、他のターゲットはターゲットレベルのままです。ディスカバリーとバッチ機能の詳細については、[Struo のテストガイド](https://struo.run/docs/guide/graph/testing)に従ってください。

## ホスト型プランを作成する {#create-a-hosted-plan}

プランニングジョブでは、この CI 実行で共有されるリファレンスを使用します。

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

レスポンスには、ホスト型プラン ID と実際のワーカーインデックスが含まれます。

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI マトリクスは `shards` から構築し、4つのエントリが含まれていると想定しないでください。空のプランは空の ID と配列を返すため、ワーカーを起動する必要はありません。プランを絞り込むには `--target` を渡し、Struo のグラフベースの選択を使用するには `--changed-path` を繰り返し指定してください。

リファレンスのデフォルト値は `TUIST_SHARD_REFERENCE` または検出された CI 実行です。環境にサポートされている CI 識別子がない場合は、明示的に渡してください。

## 各シャードを実行する {#execute-each-shard}

各ワーカーに返されたプラン ID と独自のインデックスを指定します。

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

あるいは、`TUIST_SHARD_PLAN_ID` と `TUIST_SHARD_INDEX` を設定します。ワーカーは正確な UUID に紐づいたプランをダウンロードし、割り当てられたバッチのみを実行します。割り当てが空の場合、何も実行されません。結果の欠落、プロセスの失敗、および中断された作業はパーティションを通過できません。

これはテストプランを分散させるものであり、事前コンパイルされたテストビルドアーカイブではありません。ワーカー上で必要なソース、ツール、およびディスカバリーを準備してください。共有キャッシュを利用することで、対象となるビルド作業の重複を回避できます。

## 再実行と結果 {#reruns-and-results}

再実行の場合は、`--shard-attempt` を増やすか、`TUIST_SHARD_ATTEMPT` を設定します。それ以外の場合、Struo は GitHub の実行試行回数を使用し、デフォルトは 1 です。`--shard-report-revision` のデフォルトは 0 で、同じ試行内でレポートを修正する際に増やすことができます。これらのカウンターは、テストの再試行とは別物です。

**Tests → Shards** を開いてプラン、バランス、および報告されたワーカーを確認し、その後、結合されたテスト実行を開いて個別の結果を確認します。Struo のスケジューリング単位は **Batches** と表示されます。各ケースは、元のターゲット、スイート、およびテスト名を保持します。

レポートの詳細とカバレッジの制限事項については、<.localized_link href="/guides/features/test-insights/struo">Struo テストインサイト</.localized_link>を参照してください。
