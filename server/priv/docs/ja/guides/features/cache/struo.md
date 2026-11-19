---
{
  "title": "Struo キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist のリモートキャッシュを使って、開発者マシンや CI 間で Struo アクションの結果を共有します。"
}
---
# Struo キャッシュ {#struo-cache}

<a id="once-cache"></a>

Struo はローカルで結果を再利用できますが、開発者のローカルキャッシュはチームメンバーや新しい CI ワーカーには届きません。Tuist は共有リモートキャッシュを提供し、一致する処理を 1 台のマシンでのみ実行すれば済むようにします。

## セットアップ {#setup}

<.localized_link href="/guides/get-started/struo-project#connect-the-project">Struo を使い始める</.localized_link> を完了し、リポジトリの `struo.toml` でキャッシュバインディングを確認してください。

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

`struo auth login --provider tuist` で認証します。Tuist の実行ファイルや追加のキャッシュプラグインは不要です。同じプロバイダーは [キャッシュ可能なスクリプト](https://struo.run/docs/guide/scripted/caching) と [グラフターゲット](https://struo.run/docs/guide/graph) をサポートします。

Struo によってキャッシュ可能と宣言された処理のみ再利用できます。処理が依存する入力、出力、環境を宣言してください。リモートキャッシュを設定しても、任意のコマンドが再現可能になるわけではありません。

## 共有再利用の確認 {#verify-shared-reuse}

入力と設定が一致する 2 台のマシンで、同じキャッシュ可能なスクリプトまたはグラフターゲットを実行します。

```bash
struo build MyApplication
```

1 台目のマシンが共有キャッシュにデータを格納します。その結果をローカルキャッシュに持っていない 2 台目のマシンでは、キャッシュヒットと出力の復元によりリモート再利用が確認されます。1 台目のマシンだけでコマンドを繰り返すとローカルヒットを示すことはできますが、Tuist が結果を提供したことを示すわけではありません。

## キャッシュアクティビティの確認 {#inspect-cache-activity}

Tuist プロジェクトで **Struo Cache** を開き、アクションキャッシュのヒット、転送、レイテンシ、スループットを確認します。実行の **Cache** ビューを開き、報告されたアクションの決定とコンテンツオブジェクトのアクティビティを確認します。

アクションの結果とコンテンツオブジェクトは異なる質問に答えます。アクションの結果がない場合、Struo は処理を実行する必要があります。一方、コンテンツオブジェクトのリクエストは入力または出力を転送します。ブロブのダウンロードを実行済みアクションやアクションキャッシュヒットとして扱わないでください。

実行のアクショングラフと構造化エラーについては、<.localized_link href="/guides/features/build-insights/struo">Struo ビルドインサイト</.localized_link> を参照してください。

## 継続的インテグレーション {#continuous-integration}

<.localized_link href="/guides/integrations/continuous-integration#struo">継続的インテグレーションでの Struo</.localized_link> で説明されているとおり、`TUIST_TOKEN` または Struo のヘッドレス OIDC ログインを使用します。認証情報は `struo.toml` に含めないでください。

アカウントの <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">キャッシュアップロードポリシー</.localized_link> により、結果を公開できるユーザーが決まります。読み取り専用の開発者は、キャッシュ書き込み権限を持たなくても、CI が生成したエントリを利用できます。

接続のリトライとトラブルシューティングについては、[Struo の Tuist 統合](https://struo.run/docs/guide/infrastructure/tuist#connection-recovery) を参照してください。リトライによって中断されたアップロードを再開可能にするものではありません。
