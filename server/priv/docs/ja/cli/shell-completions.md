---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Tuist****
をグローバルにインストールしている場合（Homebrew経由など）、BashとZsh用のシェル補完機能をインストールして、コマンドとオプションをオートコンプリートすることができる。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
グローバルインストールとは、シェルの`$PATH` 環境変数で利用可能なインストールのことです。つまり、ターミナル内のどのディレクトリからでも`tuist`
を実行できます。これが Homebrew のデフォルトのインストール方法です。
<!-- -->
:::

#### ジーエスエイチ{#zsh}

oh-my-zsh](https://ohmyz.sh/)がインストールされている場合、自動的にロードされる補完スクリプトのディレクトリ
-`.oh-my-zsh/completions` が既にあります。新しい補完スクリプトをそのディレクトリの`_tuist`
という新しいファイルにコピーします：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`
がない場合は、関数パスに補完スクリプト用のパスを追加し、補完スクリプトのオートロードをオンにする必要があります。まず、以下の行を`~/.zshrc`
に追加します：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion` にディレクトリを作成し、補完スクリプトを新しいディレクトリにコピーします。`_tuist`
という名前のファイルにコピーします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### バッシュ{#bash}

bash-completion](https://github.com/scop/bash-completion)
がインストールされていれば、新しい補完スクリプトをファイル`/usr/local/etc/bash_completion.d/_tuist`
にコピーするだけです：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completion がない場合、補完スクリプトを直接ソースする必要があります。`~/.bash_completions/`
などのディレクトリにコピーし、`~/.bash_profile` または`~/.bashrc` に以下の行を追加します：

```bash
source ~/.bash_completions/example.bash
```

#### 魚{#fish}

fish
shell](https://fishshell.com)を使用する場合は、新しい補完スクリプトを`~/.config/fish/completions/tuist.fish`
にコピーします：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
