---
{
  "title": "Rust プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Rust プロジェクトを Tuist に接続して、ドキュメントテストを含むビルドとテストを追跡し、不安定なテストを検出します。"
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

Tuist は既存の Cargo プロジェクトと連携します。Rust 依存関係を追加したり、プロジェクトのビルド方法を変更する必要はありません。

## プロジェクトを接続する

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> と Rust をインストールしてください。ダッシュボードでビルドシステムに **Cargo (Rust)** を指定してプロジェクトを作成します。リポジトリのルートに `tuist.toml` を追加します：

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

`tuist auth login` でログインし、通常の Cargo コマンドを Tuist 経由で実行します。CI では、CI プロバイダーの OIDC アイデンティティで認証するか、`TUIST_TOKEN` を <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> に設定します。設定ファイルを追加する代わりに `TUIST_PROJECT` を設定したり、セルフホスト型サーバーを使用する場合は `TUIST_URL` を設定することもできます。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

機能、ツールチェーン、テストフィルターなど、通常 Cargo に渡すのと同じ引数を使用します。Tuist がレポートをアップロードできない場合でも、Cargo は通常の出力と終了コードを維持します。

## Cargo の入力を続ける

[mise のコマンドラッパー](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) を有効にして、これを `mise.toml` に追加します：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

ラッパーを追加した後、`mise reshim` を実行します。その後、通常どおり `cargo build`、`cargo check`、および `cargo test` を使用できます。Mise がそれらを Tuist 経由で実行します。

> [!TIP] Coding agents
> コーディングエージェントを使用する際に便利です：`cargo build` や `cargo test` を実行する際に、`tuist` プレフィックスを追加することを思い出させる必要がありません。

## コンパイルキャッシュ

`tuist cargo build` は、対象となるコンパイル、依存関係、ビルドスクリプトの実行をローカルおよび Kura のリモートキャッシュを通じて自動的にキャッシュします。追加のツールやキャッシュ設定は不要です。このキャッシュは実験的な機能で、Apple silicon Mac で検証済みですが、すべてのコンパイルを対象としているわけではありません。サポートされているコンパイル、認証、および再利用の確認方法については、<.localized_link href="/guides/features/cache/rust">Rust キャッシュ</.localized_link> を参照してください。

## ビルドインサイト

ダッシュボードで **ビルド** を開き、ビルドにかかる時間を確認し、ローカルビルドと CI を比較します。ビルドを選択して、コンパイルに最も時間がかかったクレートを見つけ、警告やエラーを検査します。

コンパイラの計測時間はクレート単位であり、個々のソースファイルではありません。ビルドレポートの読み方については、<.localized_link href="/guides/features/build-insights/rust">Rust ビルドインサイト</.localized_link> を参照してください。

## テストインサイト

通常どおりテストを実行します：

```sh
tuist cargo test --workspace
```

ダッシュボードで **テスト** を開き、doctest を含む合格、不合格、無視されたテストを確認します。Cargo はスイートの所要時間を報告しますが、安定版の libtest はテストごとの計測時間を公開しません。

doctest だけを実行するには：

```sh
tuist cargo test --doc
```

詳細は <.localized_link href="/guides/features/test-insights/rust">Rust テストインサイト</.localized_link> および <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不安定なテスト</.localized_link> を参照してください。
