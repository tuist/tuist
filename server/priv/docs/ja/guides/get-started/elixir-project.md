---
{
  "title": "Elixir プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Elixir の依存関係キャッシュ、ビルドとテストのインサイト、不安定なテストの検出、オプションのテストシャーディングのために Tuist を一度設定します。"
}
---
# Elixir プロジェクト {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist を一度セットアップすれば、あとは `mix compile` と `mix test` を使い続けるだけです。`tuist_ex` Hex パッケージは対応する依存関係をキャッシュし、ビルドとテスト実行をダッシュボードに報告します。

## 前提条件

- Elixir 1.18 以降で Mix を使って構築された Elixir プロジェクト。
- Tuist アカウント。

## Tuist のセットアップ {#set-up-tuist}

Tuist ダッシュボードでプロジェクトを作成し、ビルドシステムとして **Mix (Elixir)** を選択します。パッケージを `mix.exs` の依存関係に追加してください。

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

パッケージを取得し、プロジェクトを設定してログインします。

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

セットアップにより `mix.exs` がプロジェクトハンドルで更新され、依存関係のキャッシュが有効になり、コンパイルとテストのエイリアスがインストールされます。他の設定や Phoenix のデータベース設定などの標準的なテスト準備は維持されます。カスタムエイリアスを安全に統合できない場合は、ファイルを変更せずに処理を停止します。

チームと CI で同じセットアップを使用できるよう、更新された `mix.exs` をコミットしてください。コピーすべきスクリプトや評価コードはありません。ログインするとブラウザが開きます。ヘッドレスログインや CI の認証情報については <.localized_link href="/guides/install-hex-package#authenticate">認証</.localized_link> を参照してください。

いつものコマンドを実行します。

```bash
mix compile
mix test
```

ビルドは **Builds** に、テスト実行は **Tests** に、依存関係のキャッシュアクティビティは **Mix cache** に表示されます。これらはすべて共通のセットアップです。不安定なテストの検出には報告された実行結果を使用します。リトライや CI でのシャーディングはオプションです。

## 依存関係のキャッシュ

Tuist は依存関係リストなしで、対応する Hex および Git の依存関係を自動的に選択します。キャッシュミスが発生すると通常通りコンパイルして結果を保存し、キャッシュヒットの場合はそれを復元します。ネイティブ/カスタムコンパイルとローカル依存関係は Mix のままです。

コンパイルは再現可能である必要があります。追加のコンパイル時入力を宣言し、モデル化されていない入力や必要な副作用を持つ依存関係を除外してください。サポートされる入力、キャッシュの検証、カスタマイズについては <.localized_link href="/guides/features/cache/elixir">Elixir キャッシュ</.localized_link> を参照してください。

## ビルドのインサイト

ビルド時間、ファイル間の依存関係グラフ、そしてそれらが時間とともにどのように変化するかを確認することで、ビルドグラフを最適化し、コンパイルが行われる環境で利用可能なすべてのコアを最大限に活用するために必要な情報が得られます。

`compile` エイリアスが設定されていると、Tuist はすべてのビルドを報告します。所要時間、警告とエラー、各ファイルのコンパイル時間、および依存しているファイルです。次の `mix compile` の後にダッシュボードの **Builds** を開いて確認してください。

## テストのインサイト

Tuist はすべての `mix test` 実行における各テストの結果と所要時間を記録するため、テストスイートが時間とともにどのように変化するかを確認したり、遅いテストや以前より遅くなったテストを見つけたり、CI で実行が失敗した理由を理解したりできます。ダッシュボードの **Tests** で、モジュール、`describe` ブロック、個々のテストまで確認できます。

## 不安定なテスト

不安定なテストは、同じコードで成功と失敗を繰り返します。Tuist は、CI で同じコミットに対して失敗と成功の両方が発生したテストを不安定としてマークします。また、パッケージに失敗したテストを再試行させることもでき、1 回の実行でそれらを検出できます。

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

再試行で成功したテストは不安定として報告され、実行は成功します。**Flaky Tests** ページに一覧表示されます。

## テストのシャーディング

テストのシャーディングは、テストスイートを複数の CI ランナーに分散します。Tuist は過去の実行で各テストファイルにかかった時間に基づいてシャードのバランスを取り、プロジェクトを一度コンパイルしてそのビルドをすべてのランナーで共有します。シャードを計画するには次のコマンドを使用します。

```bash
mix tuist.test.build --shard-max 4
```

各ランナーは `TUIST_SHARD_INDEX` を設定して自分の担当分を実行し、結果はダッシュボード上で単一のテスト実行として集約されます。

```bash
TUIST_SHARD_INDEX=0 mix test
```

## チームを巻き込む

インサイトはプロジェクトに関連付けられた人数に応じて蓄積されます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの `mix tuist.login` ではなくクリックだけで完了できるようにしましょう。

CI では個人用ログインを使用しないでください。GitHub Actions、CircleCI、Bitrise は OpenID Connect を介して認証できます。その他のプロバイダーでは、スコープを限定した `TUIST_TOKEN` を設定してください。<.localized_link href="/guides/install-hex-package#authenticate">CI 認証手順</.localized_link> に従ってください。
