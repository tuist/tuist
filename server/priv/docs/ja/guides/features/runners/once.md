---
{
  "title": "リモート実行の一度きり処理",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Tuist の Linux リモート実行ワーカーで、対応する Once グラフコマンドアクションを実行します。"
}
---
# Once リモート実行 {#once-remote-execution}

共有キャッシュにより、他のマシンで完了済みの作業を繰り返す必要がなくなります。リモート実行では、対象となるキャッシュミスをローカルからオフロードします。Once は Tuist の使い捨て Linux ワーカー上でグラフコマンドのアクションをスケジュールし、同じプロジェクトキャッシュを通じてその出力を取得します。

> [!IMPORTANT]
> **要件**
>
> - リモート実行が有効で、利用可能な実行キャパシティを備えた Tuist アカウント。
> - Tuist のリモート実行をサポートする Once のバージョン。
> - ワーカーイメージ、キャッシュエンドポイント、同時実行数、絶対パスの実行ディレクトリを告知する互換性のあるサーバー。ディレクトリを省略するサーバーは現在の Once クライアントと互換性がなく、Once は作業のアップロード前に処理を停止します。
> - 告知されたワーカーイメージ内で `linux/amd64` 上で実行できるコマンドとツールチェーン。

これはグラフアクションを実行するものであり、CI ジョブ全体を実行するものではありません。Once を構成しても、GitHub や GitLab のワークフローオーケストレーションはインストールされません。

## セットアップ {#setup}

<.localized_link href="/guides/get-started/once-project">Once の使い始め</.localized_link>を完了してください。キャッシングと実行に同じ Tuist プロバイダーを選択し、サービスが告知するワーカーイメージを固定します。

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

プロジェクトのキャッシュの読み書きが可能な認証情報で認証し、リモート実行をリクエストします。

```bash
once build --remote MyTarget
```

ターゲットとイメージタグを自分のものに置き換えてください。Once は作業をアップロードする前に、告知されたイメージ、実行ディレクトリ、キャッシュ宛先、アカウントのキャパシティを確認します。キャッシュと実行は同じプロジェクトを指している必要があります。

## ワーカー向けのアクションの準備 {#prepare-actions-for-workers}

- 入力と出力を宣言します。出力はアクションの作業ディレクトリ配下に留める必要があります。
- ツールは起動元のコンピューターの絶対パスではなく、ワーカーイメージ内で解決してください。
- 再実行しても安全なアクションを使用してください。ワーカーの障害やサービスの再起動により、別の実行が発生する可能性があります。
- タイムアウトはサービスの 10 分間のアクション制限内に収めてください。ネットワーク拒否など、サポートされていない要件は、サイレントでローカル実行されるのではなく失敗します。

Once はアカウントが告知するアクションの同時実行数を尊重し、サービスのキューがいっぱいになるとバックオフします。イメージを変更するとビルド設定とキャッシュされた結果が分離され、互換性のないワーカーイメージ間での再利用が防止されます。

キューイング、認証の更新、キャッシュエンドポイントの上書きについては、[Once のリモート実行ガイド](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)を参照してください。結果の実行を検査するには、<.localized_link href="/guides/features/build-insights/once">Once ビルドインサイト</.localized_link>に従ってください。
