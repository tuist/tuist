---
{
  "title": "シェルの補完",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist コマンドを自動補完するためのシェル設定方法を学びます。"
}
---
# シェルの補完 {#shell-completions}

Tuist を **グローバルにインストール** している場合（例: Homebrew 経由）、Zsh、Bash、Fish のシェル補完をインストールして、コマンドやオプションの自動補完を有効にできます。

> [!NOTE]
> **グローバルインストールとは**
>
> グローバルインストールとは、シェルの `$PATH` 環境変数で利用可能なインストールのことです。これにより、ターミナル内のどのディレクトリからでも `tuist` を実行できます。これは Homebrew のデフォルトのインストール方法です。


## Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/) がインストールされている場合、補完スクリプトを自動読み込みするディレクトリ `.oh-my-zsh/completions` がすでに存在します。新しい補完スクリプトをそのディレクトリ内の `_tuist` という名前のファイルにコピーしてください。

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh` がない場合は、関数パスに補完スクリプトのパスを追加し、補完スクリプトの自動読み込みを有効にする必要があります。まず、以下の行を `~/.zshrc` に追加してください。

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion` にディレクトリを作成し、補完スクリプトを新しいディレクトリにコピーします。ここでもファイル名は `_tuist` とします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion) がインストールされている場合は、新しい補完スクリプトを bash-completion のディレクトリにコピーするだけで構いません。

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

bash-completion がない場合は、補完スクリプトを直接 source する必要があります。`~/.bash_completions/` などのディレクトリに書き出してください。

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

その後、以下の行を `~/.bash_profile` または `~/.bashrc` に追加してください。

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

[fish shell](https://fishshell.com) を使用している場合は、新しい補完スクリプトを `~/.config/fish/completions/tuist.fish` にコピーできます。

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
