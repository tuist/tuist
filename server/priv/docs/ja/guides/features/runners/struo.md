---
{
  "title": "Struo リモート実行",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "対象となる Struo グラフコマンドのアクションを、Tuist の Linux リモート実行ワーカーで実行します。"
}
---
# Struo リモート実行 {#struo-remote-execution}

<a id="once-remote-execution"></a>

共有キャッシュにより、他のマシンで既に完了した作業の繰り返しを回避できます。リモート実行では、対象となるキャッシュミスをローカルマシンからオフロードします。Struo はグラフコマンドのアクションを Tuist の使い捨て Linux ワーカー上でスケジュールし、同じプロジェクトキャッシュを通じてその出力を取得します。

> [!NOTE]
> リモート実行は現在、招待制です。アカウントへのアクセスをリクエストするには [お問い合わせ](mailto:contact@tuist.dev) ください。

> [!IMPORTANT]
> **要件**
>
> - リモート実行が有効で、利用可能な実行キャパシティを備えた Tuist アカウント。
> - Tuist のリモート実行をサポートする Struo バージョン。
> - ワーカーイメージ、キャッシュエンドポイント、同時実行数、絶対パスの実行ディレクトリを広告する互換性のあるサーバー。ディレクトリを省略するサーバーは現在の Struo クライアントと互換性がなく、Struo はワークのアップロード前に処理を停止します。
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

ターゲットとイメージタグを自分のものに置き換えてください。Struo はワークをアップロードする前に、広告されたイメージ、実行ディレクトリ、キャッシュ宛先、およびアカウントのキャパシティを確認します。キャッシュと実行は同じプロジェクトを指している必要があります。

## ワーカー向けのアクションを準備する {#prepare-actions-for-workers}

- 入力と出力を宣言します。出力はアクションの作業ディレクトリ内に留める必要があります。
- ツールは起動元のコンピューターの絶対パスではなく、ワーカーイメージ内で解決します。
- 再実行しても安全なアクションを使用します。ワーカーの障害やサービスの再起動により、別の実行が発生する可能性があります。
- タイムアウトはサービスの 10 分間のアクション制限内に収めてください。ネットワーク拒否など、サポートされていない要件は、サイレントでローカル実行されるのではなく、失敗します。

Struo はアカウントが広告するアクションの同時実行数を尊重し、サービスキューがいっぱいになるとバックオフします。イメージを変更するとビルド構成とキャッシュされた結果が分離され、互換性のないワーカーイメージ間での再利用を防ぎます。

## リモート実行を検査する {#inspect-remote-execution}

プロジェクトのサイドバーには **リモート実行** ページがあります。**アナリティクス** カードには、選択した期間の実行回数と総実行時間が表示されます。詳細は <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">アクションの実行と使用量</.localized_link> で説明されています。Struo の実行テレメトリはまだリモート実行とローカルアクションを区別しないため、ページには実行ごとのリモートタイミングや実行中のランは表示されません。このギャップについて説明し、記録されたアクションの詳細については **ビルドラン** にリンクしています。現在実行中およびキューに入っているリモートアクションは、`get_remote_execution_activity` MCP ツールとその REST エンドポイントから利用できます。どちらもワーカーレーンではなく、実行サービスから提供されます。

キューイング、認証の更新、キャッシュエンドポイントのオーバーライドについては、[Struo のリモート実行ガイド](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) を参照してください。結果のランを検査するには、<.localized_link href="/guides/features/build-insights/struo">Struo ビルドインサイト</.localized_link> に従ってください。
