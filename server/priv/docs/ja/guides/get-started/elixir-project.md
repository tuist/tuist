---
{
  "title": "Elixirプロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Elixirの依存関係キャッシュ、ビルドとテストの分析、不安定なテストの検出、オプションのテストシャーディングのためにTuistを一度設定します。"
}
---
# Elixirプロジェクト {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuistを一度セットアップすれば、その後は`mix compile`と`mix test`を引き続き使えます。`tuist_ex` Hexパッケージは対応する依存関係をキャッシュし、ビルドとテスト実行をダッシュボードに報告します。

## 前提条件

- Elixir 1.18以降でMixを使って構築されたElixirプロジェクト。
- Tuistアカウント。

## Tuistのセットアップ {#set-up-tuist}

Tuistダッシュボードでプロジェクトを作成し、ビルドシステムとして**Mix (Elixir)** を選択します。パッケージを`mix.exs`の依存関係に追加してください。

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得してプロジェクトを設定し、ログインします。

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

セットアップは`mix.exs`をプロジェクトハンドルで更新し、依存関係のキャッシュを有効にして、compileおよびtestエイリアスをインストールします。他の設定やPhoenixのデータベースセットアップなどの標準的なテスト準備は維持されます。カスタムエイリアスを安全に統合できない場合は、ファイルを変更せずに処理を停止します。

チームとCIが同じセットアップを使うよう、更新した`mix.exs`をコミットしてください。コピーすべきスクリプトや評価コードはありません。ログインするとブラウザが開きます。ヘッドレスログインやCIの認証情報については<.localized_link href="/guides/install-hex-package#authenticate">認証</.localized_link>をご覧ください。

普段どおりのコマンドを実行します。

```bash
mix compile
mix test
```

ビルドは**Builds**、テスト実行は**Tests**、依存関係のキャッシュアクティビティは**Mix cache**に表示されます。これらはすべて共通のセットアップです。不安定なテストの検出には報告された実行を使用します。リトライやCIでのシャーディングはオプションです。

## 依存関係のキャッシング

Tuistは依存関係リストなしで、サポートされているHexおよびGitの依存関係を自動的に選択します。キャッシュミスの場合は通常どおりコンパイルして結果を保存し、キャッシュヒットの場合はそれを復元します。ネイティブ/カスタムコンパイルとローカル依存関係はMixのままです。

コンパイルは再現可能である必要があります。追加のコンパイル時入力を宣言し、モデル化されていない入力や必須の副作用を持つ依存関係を除外してください。サポートされる入力、キャッシュ検証、カスタマイズについては<.localized_link href="/guides/features/cache/elixir">Elixirキャッシュ</.localized_link>をご覧ください。

## ビルドインサイト

ビルド時間、ファイル間の依存関係グラフ、そしてそれらが時間とともにどう変化するかを知ることで、ビルドグラフを最適化し、コンパイルが行われる環境で利用可能なすべてのコアを最大限に活用できます。

`compile`エイリアスが有効になっていると、Tuistはすべてのビルドを報告します。所要時間、警告とエラー、各ファイルのコンパイル時間、および依存ファイルが含まれます。次の`mix compile`の後にダッシュボードの**Builds**を開いて確認してください。

## テストインサイト

Tuistはすべての`mix test`実行における各テストの結果と所要時間を記録するため、テストスイートが時間とともにどう変化するかを確認したり、遅いテストやより遅くなったテストを見つけたり、CIで実行が失敗した理由を理解したりできます。ダッシュボードの**Tests**で、モジュール単位、`describe`ブロック単位、および個々のテストまで確認できます。

## 不安定なテスト

不安定なテストは、同じコードで成功と失敗を繰り返します。Tuistは、CI上で同じコミットにおいて失敗と成功の両方が発生したテストを不安定としてマークします。また、パッケージに失敗したテストを再試行させることもでき、単一の実行でそれらを検出できます。

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

再試行で成功したテストは不安定として報告され、実行は成功します。**Flaky Tests**ページに一覧表示されます。

## テストのシャーディング

テストのシャーディングは、テストスイートをCIランナー間で分散します。Tuistは以前の実行における各テストファイルの所要時間に基づいてシャードのバランスを取り、プロジェクトを一度コンパイルしてそのビルドをすべてのランナーで共有します。シャードを計画するコマンドは1つだけです。

```bash
mix tuist.test.build --shard-max 4
```

各ランナーは`TUIST_SHARD_INDEX`を設定して自分の担当分を実行し、結果はダッシュボード上に単一のテスト実行として集約されます。

```bash
TUIST_SHARD_INDEX=0 mix test
```

## チームを巻き込む

インサイトはプロジェクトに接続している人数に応じて蓄積されます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ずつ`mix tuist.login`を行うのではなくクリックだけで完了できるようにします。

CIでは個人用ログインを使用しないでください。GitHub Actions、CircleCI、BitriseはOpenID Connect経由で認証できます。他のプロバイダーでは、スコープを限定した`TUIST_TOKEN`を設定してください。<.localized_link href="/guides/install-hex-package#authenticate">CI認証手順</.localized_link>に従ってください。
