---
{
  "title": "Rust プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Rust プロジェクトを Tuist に接続して、ドックテストを含むビルドとテストを追跡し、不安定なテストを検出します。"
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

- Cargo でビルドされる Rust プロジェクト。
- Tuist CLI と Tuist アカウント。

Tuist は既存の Cargo プロジェクトと連携します。Rust の依存関係を追加したり、プロジェクトのビルド方法を変更する必要はありません。

## プロジェクトを接続する

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> と Rust をインストールしてください。ダッシュボードでビルドシステムとして **Cargo (Rust)** を指定してプロジェクトを作成します。リポジトリのルートに `tuist.toml` を追加します:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

`tuist auth login` でログインし、その後 Tuist を介して通常の Cargo コマンドを実行します。CI では、`TUIST_TOKEN` にプロジェクトトークンを設定します。設定ファイルを追加する代わりに `TUIST_PROJECT` を設定したり、セルフホスト型サーバーを使用している場合は `TUIST_URL` を設定することもできます。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

機能、ツールチェーン、テストフィルターなど、通常 Cargo に渡すのと同じ引数を使用します。Tuist がレポートをアップロードできない場合でも、Cargo は通常の出力と終了コードを維持します。

## Cargo コマンドをそのまま入力

[mise のコマンドラッパー](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) を有効にして、これを `mise.toml` に追加します:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

ラッパーを追加した後、`mise reshim` を実行します。その後、通常どおり `cargo build`、`cargo check`、および `cargo test` を使用できます。Mise がそれらを Tuist を介して実行します。

> [!TIP] Coding agents
> コーディングエージェントを使用する際に便利です。`tuist` プレフィックスを追加することを思い出さなくても、`cargo build` や `cargo test` を引き続き実行できます。

## コンパイルキャッシュ

`tuist cargo build` は、対象となるレジストリのリーフライブラリをローカルおよび Kura のリモートキャッシュを通じて自動的にキャッシュします。追加のツールやキャッシュ設定は不要です。このキャッシュは実験的なものであり、すべてのコンパイルや異なるチェックアウトパス間での再利用はまだカバーされていません。サポートされているコンパイル、認証、および再利用の確認方法については、<.localized_link href="/guides/features/cache/rust">Rust キャッシュ</.localized_link> を参照してください。

## ビルドインサイト

ダッシュボードで **Builds** を開き、ビルドにかかる時間を確認し、ローカルビルドと CI を比較します。ビルドを選択して、コンパイルに最も時間がかかったクレートを見つけ、その警告とエラーを検査します。

コンパイラの計測時間は個別のソースファイルではなく、クレート単位です。ビルドレポートの読み方については、<.localized_link href="/guides/features/build-insights/rust">Rust ビルドインサイト</.localized_link> を参照してください。

## テストインサイト

通常どおりテストを実行します:

```sh
tuist cargo test --workspace
```

ダッシュボードで **Tests** を開き、doctest を含む合格、不合格、無視されたテストを確認します。Cargo はスイートの所要時間を報告しますが、安定版の libtest はテストごとの計測時間を公開しません。

doctest だけを実行するには:

```sh
tuist cargo test --doc
```

詳細は <.localized_link href="/guides/features/test-insights/rust">Rust テストインサイト</.localized_link> および <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不安定なテスト</.localized_link> を参照してください。
