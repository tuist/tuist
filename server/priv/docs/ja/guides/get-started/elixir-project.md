---
{
  "title": "Elixir project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Set up Tuist once for Elixir dependency caching, build and test insights, flaky test detection, and optional test sharding."
}
---
# Elixirプロジェクト {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuistを一度セットアップすれば、その後は`mix compile`と`mix test`を引き続き使用できます。`tuist_ex` Hexパッケージはサポートされている依存関係をキャッシュし、ビルドおよびテスト実行をダッシュボードに報告します。

## 前提条件

- Elixir 1.18以降でMixを使用して構築されたElixirプロジェクト。
- Tuistアカウント。

## Tuistのセットアップ {#set-up-tuist}

Tuist ダッシュボードでプロジェクトを作成し、ビルドシステムとして **Mix (Elixir)** を選択します。パッケージを `mix.exs` の依存関係に追加します:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得し、プロジェクトを設定してログインします：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

セットアップにより`mix.exs`がプロジェクトハンドルで更新され、依存関係のキャッシングが有効になり、コンパイルおよびテストのエイリアスがインストールされます。Phoenixのデータベース設定などの他の設定や標準的なテスト準備は保持されます。カスタムエイリアスを安全に統合できない場合、ファイルを変更せずに処理を停止します。

チームとCIが同じセットアップを使用できるよう、更新された`mix.exs`をコミットします。コピーすべきスクリプトや評価コードはありません。ログインするとブラウザが開きます。ヘッドレスログインとCI認証情報については<.localized_link href="/guides/install-hex-package#authenticate">認証</.localized_link>を参照してください。

通常のコマンドを実行します：

```bash
mix compile
mix test
```

ビルドは**Builds**の下に、テスト実行は**Tests**の下に、依存関係キャッシュのアクティビティは**Mix cache**の下に表示されます。これは3つすべてに共通するセットアップです。不安定なテストの検出には報告された実行結果が使用されます。再試行とCIシャーディングはオプションです。

## 依存関係のキャッシング

Tuistは依存関係リストなしで、サポートされているHexおよびGit依存関係を自動的に選択します。キャッシュミスが発生した場合は通常通りコンパイルして結果を保存し、キャッシュヒットの場合はそれを復元します。ネイティブ/カスタムコンパイルとローカル依存関係はMixのまま残ります。

コンパイルは再現可能である必要があります：追加のコンパイル時入力を宣言し、モデル化されていない入力や必要な副作用を持つ依存関係を除外します。サポートされている入力、キャッシュ検証、およびカスタマイズについては<.localized_link href="/guides/features/cache/elixir">Elixirキャッシュ</.localized_link>を参照してください。

## ビルドインサイト

ビルド時間、ファイル間の依存関係グラフ、およびそれらが時間とともにどのように変化するかを知ることで、ビルドグラフを最適化し、コンパイルが行われる環境で利用可能なすべてのコアを最大限に活用するために必要な情報が得られます。

`compile`エイリアスが設定されている状態で、Tuistはすべてのビルドを報告します：所要時間、警告とエラー、各ファイルのコンパイル時間、および依存しているファイル。次の`mix compile`の後、ダッシュボードの**Builds**を開いて確認してください。

## テストインサイト

Tuistはすべての`mix test`実行における各テストの結果と持続時間を記録するため、テストスイートが時間とともにどのように変化するかを確認したり、遅いテストやより遅くなったテストを見つけたり、CIで実行が失敗した理由を理解したりできます。ダッシュボードの**Tests**の下で、モジュール、`describe`ブロック、および個々のテストまで確認できます。

## 不安定なテスト

不安定なテストとは、同じコードで成功と失敗を繰り返すテストです。Tuistは、CI上で同じコミットにおいて失敗と成功の両方が発生したテストを不安定としてマークします。また、パッケージに失敗したテストを再試行させることもでき、これにより1回の実行で検出できます：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

再試行で成功したテストは不安定として報告され、実行は成功となります。**Flaky Tests**ページに一覧表示されます。

## テストシャーディング

テストシャーディングは、テストスイートをCIランナー間で分散させます。Tuistは以前の実行における各テストファイルの所要時間を使用してシャードのバランスを取り、プロジェクトを1回コンパイルしてそのビルドをすべてのランナーで共有します。1つのコマンドでシャードを計画します：

```bash
mix tuist.test.build --shard-max 4
```

各ランナーは`TUIST_SHARD_INDEX`が設定された状態で自身の分担部分を実行し、結果はダッシュボード上に単一のテスト実行として届きます：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## チームを巻き込む

インサイトはプロジェクトに関連付けられた人数に応じて累積していきます。ダッシュボードのアカウント設定からチームメンバーを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの`mix tuist.login`ではなくクリックだけで完了できるようにします。

CIでは個人用ログインを使用しないでください。GitHub Actions、CircleCI、BitriseはOpenID Connectを通じて認証できます。その他のプロバイダーでは、スコープ付きの`TUIST_TOKEN`を設定してください。<.localized_link href="/guides/install-hex-package#authenticate">CI認証手順</.localized_link>に従ってください。
