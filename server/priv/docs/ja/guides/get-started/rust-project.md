---
{
  "title": "Rustプロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "RustプロジェクトをTuistに接続して、ドックテストを含むビルドとテストを追跡し、不安定なテストを検出します。"
}
---
# Rustプロジェクト {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 前提条件

- CargoでビルドされたRustプロジェクト。
- Tuist CLIとTuistアカウント。

Tuistは既存のCargoプロジェクトで動作します。Rust依存関係を追加したり、プロジェクトのビルド方法を変更する必要はありません。

## プロジェクトを接続する

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>とRustをインストールします。ダッシュボードでビルドシステムとして**Cargo (Rust)** を選択してプロジェクトを作成します。その後、ワークスペースのルートにある`Cargo.toml`にプロジェクトを追加します。

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargoは`metadata`テーブルを無視するため、プロジェクトのビルド方法は変わりません。`[workspace]`テーブルを持たない単一クレートの場合、代わりに`[package.metadata.tuist]`を使用します。このテーブルは`tuist.toml`ファイルと同じ設定を受け付けるため、リポジトリに他のビルドシステム用のプロジェクトが含まれている場合などに代わりとして使用できます。両方が存在する場合、`tuist.toml`が優先されます。

`tuist auth login`でログインし、通常のCargoコマンドをTuist経由で実行します。CI環境では、CIプロバイダーのOIDC IDで認証するか、`TUIST_TOKEN`を<.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link>に設定します。構成ファイルを追加する代わりに`TUIST_PROJECT`を設定したり、セルフホスト型サーバーを使用する場合は`TUIST_URL`を設定することもできます。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

機能、ツールチェーン、テストフィルターなど、通常Cargoに渡すのと同じ引数を使用します。Tuistがレポートをアップロードできない場合でも、Cargoは通常の出力と終了コードを維持します。

## Cargoのコマンド入力を続ける

[miseのコマンドラッパー](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers)を有効にして、これを`mise.toml`に追加します。

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

ラッパーを追加した後、`mise reshim`を実行します。その後、通常どおり`cargo build`、`cargo check`、および`cargo test`を使用できます。MiseがこれらをTuist経由で実行します。

> [!TIP] Coding agents
> コーディングエージェントを使用する際に便利です。`cargo build`や`cargo test`を実行し続ける際、`tuist`プレフィックスを追加することを思い出させる必要がありません。

## コンパイルキャッシュ

`tuist cargo build`は、対象となるコンパイル、依存関係、ビルドスクリプトの実行をローカルおよびKuraのリモートキャッシュを通じて自動的にキャッシュします。追加のツールやキャッシュ設定は不要です。このキャッシュは実験的なもので、Appleシリコン搭載のMacで検証済みですが、すべてのコンパイルを対象としているわけではありません。サポートされているコンパイル、認証、および再利用の確認方法については、<.localized_link href="/guides/features/cache/rust">Rustキャッシュ</.localized_link>をご覧ください。

## ビルドインサイト

ダッシュボードで**ビルド**を開き、ビルドにかかる時間を確認したり、ローカルビルドとCIを比較します。ビルドを選択して、コンパイルに最も時間がかかったクレートを特定し、警告やエラーを確認します。

コンパイラの計測時間はソースファイル単位ではなく、クレート単位です。ビルドレポートの読み方については、<.localized_link href="/guides/features/build-insights/rust">Rustビルドインサイト</.localized_link>をご覧ください。

## テストインサイト

通常どおりテストを実行します。

```sh
tuist cargo test --workspace
```

ダッシュボードで**テスト**を開き、doctestを含む合格、不合格、無視されたテストを確認します。Cargoはスイートの経過時間を報告しますが、安定版のlibtestはテストごとの計測時間を公開しません。

doctestのみを実行するには：

```sh
tuist cargo test --doc
```

詳細は、<.localized_link href="/guides/features/test-insights/rust">Rustテストインサイト</.localized_link>および<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust不安定なテスト</.localized_link>をご覧ください。

## 商標 {#trademarks}

RustおよびCargoはRust Foundationの商標です。TuistはRust ProjectまたはRust Foundationと提携しておらず、推奨もされていません。これらのガイドで使用されているRustロゴは© Rust Foundationであり、[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)に基づいて使用され、ページのテーマに沿った単色で表示されています。
