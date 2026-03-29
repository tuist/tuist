---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Tuist**をグローバルにインストールしている場合**
（例：Homebrew経由）、BashおよびZsh用のシェル補完機能をインストールして、コマンドやオプションを自動補完することができます。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
グローバルインストールとは、シェルの` 、$PATH、`
環境変数で利用可能なインストール方法です。これにより、ターミナル内のどのディレクトリからでも`tuist`
を実行できます。これはHomebrewのデフォルトのインストール方法です。
<!-- -->
:::

#### Zsh{#zsh}

[oh-my-zsh](https://ohmyz.sh/)
をインストールしている場合、自動的に読み込まれる補完スクリプト用のディレクトリ（`.oh-my-zsh/completions`
）が既に存在します。新しい補完スクリプトを、そのディレクトリ内に`_tuist` という名前の新しいファイルとしてコピーしてください：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`
を使用しない場合は、補完スクリプトのパスを関数パスに追加し、補完スクリプトの自動読み込みを有効にする必要があります。まず、`~/.zshrc`
に以下の行を追加してください：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion` にディレクトリを作成し、補完スクリプトを新しいディレクトリ内の`_tuist` というファイルにコピーします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

[bash-completion](https://github.com/scop/bash-completion)がインストールされている場合は、新しい補完スクリプトを`/usr/local/etc/bash_completion.d/_tuist`
にコピーするだけで済みます：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion を使用しない場合は、補完スクリプトを直接ソースする必要があります。スクリプトを`~/.bash_completions/`
などのディレクトリにコピーし、`~/.bash_profile` または`~/.bashrc` に以下の行を追加してください：

```bash
source ~/.bash_completions/example.bash
```

#### 魚{#fish}

[fish shell](https://fishshell.com)
を使用している場合は、新しい補完スクリプトを`~/.config/fish/completions/tuist.fish` にコピーできます :

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
