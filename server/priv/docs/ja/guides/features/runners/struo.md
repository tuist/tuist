---
{
  "title": "Struo リモート実行",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "対象となる Struo グラフコマンドのアクションを、Tuist の Linux リモート実行ワーカーで実行します。"
}
---
# Struo リモート実行 {#struo-remote-execution}

<a id="once-remote-execution"></a>

共有キャッシュにより、他のマシンで完了済みの作業を繰り返す必要がなくなります。リモート実行では、対象となるキャッシュミスをローカル環境からオフロードします。Struo はグラフのコマンドアクションを Tuist の使い捨て Linux ワーカー上でスケジュールし、同じプロジェクトキャッシュを通じてその出力を取得します。

> [!NOTE]
> リモート実行は現在招待制です。アカウントへのアクセスをリクエストするには [お問い合わせ](mailto:contact@tuist.dev) ください。

> [!IMPORTANT]
> **要件**
>
> - リモート実行が有効で、利用可能な実行キャパシティを持つ Tuist アカウント。
> - Tuist のリモート実行をサポートする Struo バージョン。
> - ワーカーイメージ、キャッシュエンドポイント、同時実行数、絶対パスの実行ディレクトリを広告する互換性のあるサーバー。ディレクトリを省略するサーバーは現在の Struo クライアントと互換性がなく、Struo は作業のアップロード前に処理を停止します。
> - 広告されたワーカーイメージ内で `linux/amd64` 上で実行できるコマンドとツールチェーン。

これはグラフアクションを実行するものであり、CI ジョブ全体を実行するものではありません。Struo を構成しても、GitHub や GitLab のワークフローオーケストレーションはインストールされません。

## セットアップ {#setup}

<.localized_link href="/guides/get-started/struo-project">Struo を使い始める</.localized_link> を完了してください。キャッシングと実行に同じ Tuist プロバイダーを選択し、サービスが広告するワーカーイメージを固定します。

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

プロジェクトのキャッシュを読み書きできる認証情報で認証し、リモート実行をリクエストします。

```bash
struo build --remote MyTarget
```

ターゲットとイメージタグを各自のものに置き換えてください。Struo は作業をアップロードする前に、広告されたイメージ、実行ディレクトリ、キャッシュ宛先、アカウントのキャパシティを確認します。キャッシュと実行は同じプロジェクトを指している必要があります。

## ワーカー向けアクションの準備 {#prepare-actions-for-workers}

- 入力と出力を宣言してください。出力はアクションの作業ディレクトリ配下に留める必要があります。
- ツールは起動元コンピュータの絶対パスではなく、ワーカーイメージ内で解決してください。
- 再実行しても安全なアクションを使用してください。ワーカーの障害やサービスの再起動により、別の実行が発生する可能性があります。
- タイムアウトはサービスの 10 分間のアクション制限内に収めてください。ネットワーク拒否など、サポートされていない要件は、サイレントにローカルで実行されるのではなく失敗します。

Struo はアカウントが広告するアクションの同時実行数を尊重し、サービスのキューがいっぱいになるとバックオフします。イメージを変更するとビルド設定とキャッシュ結果が分離され、互換性のないワーカーイメージ間での再利用を防ぎます。

## リモート実行の確認 {#inspect-remote-execution}

プロジェクトのサイドバーには **リモート実行** ページがあります。**アナリティクス** カードには、選択した期間の実行回数と合計実行時間が表示されます。詳細は <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">アクションの実行と使用量</.localized_link> で説明されています。Struo 2.19.0 より後のリリースでは、各リモートアクションが所属する Struo ランに名前付けされるため、このページではキュー時間と実行時間のチャート表示や、リモートアクション・結果・タイミングを含むランの一覧（実行中のランを優先）も提供されます。ランをクリックすると **ビルドラン** でそのページが開きます。古いクライアントからのランや、リモートキャッシュから応答されたアクションはここには計上されません。現在実行中およびキューに入っているリモートアクションは、`get_remote_execution_activity` MCP ツールとその REST エンドポイントから確認できます。これらはどちらもワーカーレーンではなく、実行サービスから提供されます。

キューイング、認証の更新、キャッシュエンドポイントのオーバーライドについては [Struo のリモート実行ガイド](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) を参照してください。結果として生成されたランを確認するには <.localized_link href="/guides/features/build-insights/struo">Struo ビルドインサイト</.localized_link> に従ってください。
