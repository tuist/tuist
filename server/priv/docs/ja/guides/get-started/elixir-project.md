---
{
  "title": "Elixir プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Elixir の依存関係キャッシュ、ビルドおよびテストの分析、不安定なテストの検出、オプションのテスト分割のために Tuist を一度セットアップします。"
}
---
# Elixir プロジェクト {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist を一度セットアップすれば、その後は `mix compile` と `mix test` をそのまま使い続けられます。`tuist_ex` Hex パッケージは対応する依存関係をキャッシュし、ビルドとテスト実行をダッシュボードに報告します。

## 前提条件

- Elixir 1.18 以降で Mix を使って構築された Elixir プロジェクト。
- Tuist アカウント。

## Tuist のセットアップ {#set-up-tuist}

Tuist ダッシュボードでプロジェクトを作成し、ビルドシステムとして **Mix (Elixir)** を選択します。パッケージを `mix.exs` の依存関係に追加してください：

<!-- @snippet: ../_tuist-ex-dependency -->

取得してプロジェクトを設定し、ログインします：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

セットアップは `mix.exs` をプロジェクトハンドルで更新し、依存関係のキャッシュを有効にして、compile と test のエイリアスをインストールします。他の設定や Phoenix のデータベース設定といった標準的なテスト準備は維持されます。カスタムエイリアスを安全に統合できない場合は、ファイルを変更せずに処理を停止します。

チームと CI が同じ構成を使えるよう、更新した `mix.exs` をコミットしてください。コピーすべきスクリプトや評価コードはありません。ログインするとブラウザが開きます。ヘッドレスログインや CI 用の認証情報については <.localized_link href="/guides/install-hex-package#authenticate">認証</.localized_link> を参照してください。

いつものコマンドを実行します：

```bash
mix compile
mix test
```

ビルドは **Builds** に、テスト実行は **Tests** に、依存関係のキャッシュ活動は **Mix cache** に表示されます。これらはすべて共通のセットアップです。不安定なテストの検出には報告された実行結果を使用します。リトライや CI でのシャーディングは任意です。

## 依存関係のキャッシング

Tuist は依存関係リストなしで、サポートされている Hex および Git の依存関係を自動的に選択します。キャッシュミスが発生すると通常どおりコンパイルして結果を保存し、キャッシュヒットの場合はそれを復元します。ネイティブ/カスタムコンパイルとローカル依存関係は Mix のままです。

コンパイルは再現可能である必要があります：追加のコンパイル時入力を宣言し、モデル化されていない入力や必須の副作用を持つ依存関係を除外してください。サポートされている入力、キャッシュの検証、カスタマイズについては <.localized_link href="/guides/features/cache/elixir">Elixir キャッシュ</.localized_link> を参照してください。

## ビルドのインサイト

ビルド時間、ファイル間の依存関係グラフ、そしてそれらが時間とともにどう変化するかを追跡することで、ビルドグラフを最適化し、コンパイル環境で利用可能なすべてのコアを最大限に活用するために必要な情報が得られます。

`compile` エイリアスが有効になると、Tuist はすべてのビルドを報告します。所要時間、警告とエラー、各ファイルのコンパイル時間、および依存ファイルが含まれます。次の `mix compile` の後にダッシュボードの **Builds** を開いて確認してください。

## テストのインサイト

Tuist は `mix test` 実行ごとの各テストの結果と所要時間を記録するため、テストスイートが時間とともにどう変化するかを確認したり、遅いテストやより遅くなったテストを見つけたり、CI で実行が失敗した理由を理解できます。ダッシュボードの **Tests** で、モジュール単位、`describe` ブロック単位、およびテスト単位まで確認できます。

## 不安定なテスト

不安定なテストは、同じコードで成功と失敗を繰り返します。Tuist は、CI で同じコミットに対して失敗と成功の両方が発生したテストを不安定としてマークします。また、パッケージに失敗したテストを再試行させることで、1 回の実行でそれらを検出できます：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

再試行で成功したテストは不安定として報告され、実行は成功扱いになります。**Flaky Tests** ページに一覧表示されます。

## テストのシャーディング

テストのシャーディングは、テストスイートを複数の CI ランナーに分散します。Tuist は過去の執行における各テストファイルの所要時間に基づいてシャードのバランスを取り、プロジェクトを一度コンパイルしてそのビルド成果物をすべてのランナーで共有します。シャードの計画は 1 つのコマンドで行います：

```bash
mix tuist.test.build --shard-max 4
```

各ランナーは `TUIST_SHARD_INDEX` を設定して自身の担当分を実行し、結果はダッシュボード上で単一のテスト実行として集約されます：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## チームを巻き込む

インサイトの価値はプロジェクトに接続する人数とともに増していきます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの `mix tuist.login` ではなくクリックだけで完了できるようにしましょう。

CI では個人用ログインを使用しないでください。GitHub Actions、CircleCI、Bitrise は OpenID Connect 経由で認証できます。その他のプロバイダーでは、スコープを限定した `TUIST_TOKEN` を設定してください。<.localized_link href="/guides/install-hex-package#authenticate">CI 認証手順</.localized_link> に従ってください。
