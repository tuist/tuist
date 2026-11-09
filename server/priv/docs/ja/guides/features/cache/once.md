---
{
  "title": "Onceキャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuistのリモートキャッシュを使用して、開発者マシンやCI間でOnceアクションの結果を共有します。"
}
---
# Once キャッシュ {#once-cache}

Once はローカルで結果を再利用できますが、開発者のローカルキャッシュはチームメンバーや新しい CI ワーカーには届きません。Tuist は共有リモートキャッシュを提供するため、一致する作業は 1 台のマシンでのみ実行する必要があります。

## セットアップ {#setup}

<.localized_link href="/guides/get-started/once-project#connect-the-project">Once を使い始める</.localized_link>を完了し、リポジトリの `once.toml` でキャッシュバインディングを確認してください:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

`once auth login --provider tuist` で認証します。Tuist 実行ファイルや追加のキャッシュプラグインは不要です。同じプロバイダーは [キャッシュ可能なスクリプト](https://buildonce.dev/docs/guide/scripted/caching) と [グラフターゲット](https://buildonce.dev/docs/guide/graph) をサポートします。

Once でキャッシュ可能と宣言された作業のみが再利用可能です。作業が依存する入力、出力、環境を宣言してください。リモートキャッシュを設定しても、任意のコマンドが再現可能になるわけではありません。

## 共有再利用の確認 {#verify-shared-reuse}

入力と構成が一致する 2 台のマシンで、同じキャッシュ可能なスクリプトまたはグラフターゲットを実行します:

```bash
once build MyApplication
```

1 台目のマシンが共有キャッシュにデータを入れます。その結果をローカルキャッシュでまだ持っていない 2 台目のマシンでは、キャッシュヒットと復元された出力によってリモート再利用が確認されます。1 台目のマシンだけでコマンドを繰り返すと、ローカルキャッシュヒットを示すことはできますが、Tuist が結果を提供したことを示すものではありません。

## キャッシュアクティビティの確認 {#inspect-cache-activity}

Tuist プロジェクトで **Once Cache** を開き、アクションキャッシュのヒット、転送、レイテンシ、スループットを確認します。実行の **Cache** ビューを開き、報告されたアクションの決定とコンテンツオブジェクトのアクティビティを確認します。

アクションの結果とコンテンツオブジェクトは異なる問いに答えます。アクションの結果がない場合、Once が作業を実行する必要があります。一方、コンテンツオブジェクトのリクエストは入力または出力を転送します。Blob のダウンロードを実行済みアクションやアクションキャッシュヒットとして扱わないでください。

実行のアクショングラフと構造化エラーについては、<.localized_link href="/guides/features/build-insights/once">Once ビルドインサイト</.localized_link> を参照してください。

## 継続的インテグレーション {#continuous-integration}

`TUIST_TOKEN` または Once のヘッドレス OIDC ログインを使用します（詳細は <.localized_link href="/guides/integrations/continuous-integration#once">継続的インテグレーションでの Once</.localized_link> を参照）。認証情報は `once.toml` に含めないでください。

アカウントの <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">キャッシュアップロードポリシー</.localized_link> により、結果を公開できるユーザーが決まります。読み取り専用の開発者は、キャッシュ書き込み権限を持たなくても、CI が生成したエントリを利用できます。

接続の再試行とトラブルシューティングについては、[Once の Tuist 統合](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery) を参照してください。再試行によって中断されたアップロードを再開可能にするわけではありません。
