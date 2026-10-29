---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
}
---
# Rust プロジェクト {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 前提条件

- Cargo でビルドされた Rust プロジェクト。
- Tuist CLI と Tuist アカウント。

Tuist は既存の Cargo プロジェクトと連携します。Rust の依存関係を追加したり、プロジェクトのビルド方法を変更する必要はありません。

## プロジェクトを接続する

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> と Rust をインストールします。ダッシュボードでビルドシステムとして **Cargo (Rust)** を選択してプロジェクトを作成します。リポジトリのルートに `tuist.toml` を追加します:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

`tuist auth login` でログインし、通常の Cargo コマンドを Tuist 経由で実行します。CI では、`TUIST_TOKEN` をプロジェクトトークンに設定します。設定ファイルを追加する代わりに `TUIST_PROJECT` を設定したり、セルフホスト型サーバーを使用している場合は `TUIST_URL` を設定することもできます。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

機能、ツールチェーン、テストフィルターなど、通常 Cargo に渡すのと同じ引数を使用します。Tuist がレポートをアップロードできない場合でも、Cargo は通常の出力と終了コードを維持します。

## Cargo をそのまま入力し続ける

[mise のコマンドラッパー](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) を有効にして、これを `mise.toml` に追加します:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

ラッパーを追加した後、`mise reshim` を実行します。その後、通常通り `cargo build`、`cargo check`、および `cargo test` を使用できます。Mise がそれらを Tuist 経由で実行します。

> [!TIP] Coding agents
> コーディングエージェントと作業する際に便利です。`cargo build` および `cargo test` を実行し続けることができ、`tuist` プレフィックスを追加することを思い出させる必要がありません。

## コンパイルキャッシュ

`tuist cargo build` は、適格なレジストリのリーフライブラリをローカルおよび Kura のリモートキャッシュを通じて自動的にキャッシュします。追加のツールやキャッシュ設定は必要ありません。このキャッシュは実験的なものであり、すべてのコンパイルや異なるチェックアウトパス間での再利用はまだカバーされていません。サポートされているコンパイル、認証、および再利用の確認方法については、<.localized_link href="/guides/features/cache/rust">Rust キャッシュ</.localized_link> を参照してください。

## ビルドインサイト

ダッシュボードで **Builds** を開き、ビルドにかかる時間を確認し、ローカルビルドと CI を比較します。ビルドを選択して、コンパイルに最も時間がかかったクレートを見つけ、その警告とエラーを検査します。

コンパイラのタイミングはクレート単位であり、個々のソースファイル単位ではありません。ビルドレポートの読み方については、<.localized_link href="/guides/features/build-insights/rust">Rust ビルドインサイト</.localized_link> を参照してください。

## テストインサイト

通常通りテストを実行します:

```sh
tuist cargo test --workspace
```

ダッシュボードで **Tests** を開き、doctest を含む合格、不合格、無視されたテストを確認します。Cargo はスイートの期間を報告しますが、安定版の libtest はテストごとのタイミングを公開しません。

doctest のみを実行するには:

```sh
tuist cargo test --doc
```

詳細については、<.localized_link href="/guides/features/test-insights/rust">Rust テストインサイト</.localized_link> および <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust フレーキーテスト</.localized_link> を参照してください。
