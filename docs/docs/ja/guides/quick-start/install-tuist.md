---
title: Tuistのインストール
titleTemplate: :title · クイックスタート · ガイド · Tuist
description: 開発環境にTuistをインストールする方法を学びます
---

# Tuistのインストール {#install-tuist}

Tuist CLIは、実行可能ファイル、動的フレームワーク、およびリソースのセット (たとえば、テンプレート) で構成されています。 [ソース](https://github.com/tuist/tuist)からTuistを手動でビルドすることもできますが、**有効なインストールを確保するために、以下のインストール方法のいずれかを使用することをお勧めします。**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::info
Mise is a recommended alternative to [Homebrew](https://brew.sh) if you are a team or organization that needs to ensure deterministic versions of tools across different environments.
:::

You can install Tuist through any of the following commands:

```bash
mise install tuist            # .tool-versions/.mise.tomlに指定された現在のバージョンをインストール
mise install tuist@x.y.z      # 特定のバージョン番号をインストール
mise install tuist@3          # あいまいなバージョン番号をインストール
```

Homebrewのようなツールがグローバルに単一のバージョンをインストールしてアクティブにするのに対し、**miseではバージョンをグローバルまたはプロジェクト単位で有効にする必要があります。** これは `mise use` を実行することで行います。

```bash
mise use tuist@x.y.z          # 現在のプロジェクトでtuist-x.y.zを使用
mise use tuist@latest         # 現在のディレクトリで最新のtuistを使用
mise use -g tuist@x.y.z       # tuist-x.y.zをグローバルデフォルトとして使用
mise use -g tuist@system      # システムのtuistをグローバルデフォルトとして使用
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

You can install Tuist using [Homebrew](https://brew.sh) and [our formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

### シェルの補完 {#shell-completions}

If you have Tuist **globally installed** (e.g., via Homebrew),
you can install shell completions for Bash and Zsh to autocomplete commands and options.

:::warning グローバルインストールとは
グローバルインストールは、シェルの `$PATH` 環境変数で利用可能なインストールです。 つまり、ターミナルの任意のディレクトリから `tuist` を実行できます。 This is the default installation method for Homebrew.
:::

#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/) がインストールされている場合、自動的に読み込まれる補完スクリプトのディレクトリ `.oh-my-zsh/completions` があります。 新しい補完スクリプトをそのディレクトリに `_tuist` という名前の新しいファイルとしてコピーします。 新しい補完スクリプトをそのディレクトリに `_tuist` という名前の新しいファイルとしてコピーします。

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` がない場合、補完スクリプトのパスを関数パスに追加し、補完スクリプトの自動読み込みを有効にする必要があります。 最初に、`~/.zshrc` に以下の行を追加します。

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion` にディレクトリを作成し、補完スクリプトを新しいディレクトリに再度 `_tuist` というファイルにコピーします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion) がインストールされている場合、新しい補完スクリプトをファイル `/usr/local/etc/bash_completion.d/_tuist` にコピーするだけで済みます。

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion がない場合、補完スクリプトを直接 source で読み込む必要があります。 `~/.bash_completions/` のようなディレクトリにコピーし、次の行を `~/.bash_profile` または `~/.bashrc` に追加します。

```bash
source ~/.bash_completions/example.bash
```
