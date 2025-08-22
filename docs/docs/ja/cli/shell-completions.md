---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Tuistを**グローバルにインストールしている**場合 (例えば、Homebrew経由で)、BashやZsh用のシェル補完をインストールして、コマンドやオプションを自動補完できます。

:::warning WHAT IS A GLOBAL INSTALLATION
グローバルインストールは、シェルの `$PATH` 環境変数で利用可能なインストールです。 つまり、ターミナルの任意のディレクトリから `tuist` を実行できます。 This is the default installation method for Homebrew.
:::

#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/) がインストールされている場合、自動的に読み込まれる補完スクリプトのディレクトリ `.oh-my-zsh/completions` があります。 新しい補完スクリプトをそのディレクトリに `_tuist` という名前の新しいファイルとしてコピーします。

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

#### Fish {#fish}

If you use [fish shell](https://fishshell.com), you can copy your new completion script to `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
