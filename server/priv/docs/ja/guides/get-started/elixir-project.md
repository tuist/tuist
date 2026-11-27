---
{
  "title": "Elixir プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Elixir の依存関係キャッシュ、ビルドおよびテストのインサイト、flaky テストの検出、オプションのテストシャーディングのために Tuist を一度設定します。"
}
---
# Elixirプロジェクト {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuistを一度セットアップすれば、あとは`mix compile`と`mix test`を使い続けるだけです。`tuist_ex` Hexパッケージは対応する依存関係をキャッシュし、ビルドとテスト実行をダッシュボードに報告します。

## 前提条件

- Elixir 1.18以降でMixを使用して構築されたElixirプロジェクト。
- Tuistアカウント。

## Tuistのセットアップ {#set-up-tuist}

Tuistダッシュボードでプロジェクトを作成し、ビルドシステムとして**Mix (Elixir)** を選択します。パッケージを`mix.exs`内の依存関係に追加します：

<!-- @snippet: ../_tuist-ex-dependency -->

取得してプロジェクトを設定し、ログインします：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

セットアップにより、`mix.exs`がプロジェクトハンドルで更新され、依存関係のキャッシュが有効になり、コンパイルおよびテスト用のエイリアスがインストールされます。他の設定やPhoenixのデータベースセットアップなどの標準的なテスト準備は維持されます。カスタムエイリアスを安全に統合できない場合は、ファイルを変更せずに処理を停止します。

チームとCIが同じセットアップを使用できるよう、更新された`mix.exs`をコミットしてください。コピーすべきスクリプトや評価コードはありません。ログインするとブラウザが開きます。ヘッドレスログインやCI認証情報については<.localized_link href="/guides/install-hex-package#authenticate">認証</.localized_link>をご覧ください。

いつものコマンドを実行します：

```bash
mix compile
mix test
```

ビルドは**Builds**、テスト実行は**Tests**、依存関係のキャッシュアクティビティは**Mix cache**に表示されます。これらはすべて共通のセットアップです。不安定なテストの検出には報告された実行結果が使用されます。再試行やCIでのシャーディングはオプションです。

## 依存関係のキャッシング

Tuistは依存関係リストなしで、サポートされているHexおよびGit依存関係を自動的に選択します。キャッシュミスが発生した場合は通常通りコンパイルして結果を保存し、ヒットした場合はその結果を復元します。ネイティブ/カスタムコンパイルおよびローカル依存関係はMixのまま残ります。

コンパイルは再現可能である必要があります。追加のコンパイル時入力を宣言し、モデル化されていない入力や必須の副作用を持つ依存関係を除外してください。サポートされている入力、キャッシュの検証、カスタマイズについては<.localized_link href="/guides/features/cache/elixir">Elixirキャッシュ</.localized_link>をご覧ください。

## ビルドのインサイト

ビルド時間、ファイル間の依存関係グラフ、そしてそれらが時間とともにどのように変化するかを確認することで、ビルドグラフを最適化し、コンパイルが行われる環境で利用可能なすべてのコアを最大限に活用するために必要な情報が得られます。

`compile`エイリアスが設定されていると、Tuistはすべてのビルドを報告します。所要時間、警告とエラー、各ファイルのコンパイル時間、および依存しているファイルが含まれます。次の`mix compile`の後にダッシュボードの**Builds**を開いて確認してください。

## テストのインサイト

Tuistはすべての`mix test`実行における各テストの結果と所要時間を記録するため、テストスイートが時間とともにどのように変化するかを確認したり、遅いテストやより遅くなったテストを見つけたり、CIで実行が失敗した理由を理解したりできます。ダッシュボードの**Tests**で、モジュール、`describe`ブロック、個々のテストまで詳細に確認できます。

## 不安定なテスト

不安定なテストは、同じコードで成功と失敗を繰り返します。Tuistは、CI上の同じコミットで失敗と成功の両方が発生した場合に、そのテストを不安定としてマークします。また、パッケージに失敗したテストを再試行させることもでき、1回の実行でそれらを検出できます：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

再試行で成功したテストは不安定として報告され、実行は成功扱いになります。**Flaky Tests**ページに一覧表示されます。

## テストのシャーディング

テストのシャーディングは、テストスイートをCIランナー間で分散させます。Tuistは過去の執行結果に基づき各テストファイルの所要時間を使用してシャードのバランスを取り、プロジェクトを一度コンパイルしてそのビルドをすべてのランナーで共有します。シャードを計画するには1つのコマンドを実行します：

```bash
mix tuist.test.build --shard-max 4
```

各ランナーは`TUIST_SHARD_INDEX`を設定して自身の担当分を実行し、結果はダッシュボード上で単一のテスト実行として集約されます：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## チームを巻き込む

インサイトの効果はプロジェクトに関連付けられた人数に応じて増大します。ダッシュボードのアカウント設定からチームメンバーを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの`mix tuist.login`ではなくクリックだけで完了できるようにしましょう。

CIでは個人用ログインを使用しないでください。GitHub Actions、CircleCI、BitriseはOpenID Connect経由で認証できます。その他のプロバイダーでは、スコープを限定した`TUIST_TOKEN`を設定してください。<.localized_link href="/guides/install-hex-package#authenticate">CI認証手順</.localized_link>に従ってください。
