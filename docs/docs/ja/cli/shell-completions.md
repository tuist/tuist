---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

Tuist**をグローバルにインストール済み（例：Homebrew経由）の場合、**
でBashおよびZsh用のシェル補完をインストールし、コマンドやオプションの自動補完が可能になります。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
グローバルインストールとは、シェル環境変数（`$PATH` ）で利用可能なインストール方法です。これにより、ターミナルの任意のディレクトリから`tuist`
を実行できます。これはHomebrewのデフォルトインストール方法です。
<!-- -->
:::

#### Zsh{#zsh}

[oh-my-zsh](https://ohmyz.sh/)がインストールされている場合、自動読み込み用補完スクリプトのディレクトリが既に存在します
—`.oh-my-zsh/completions` 。新しい補完スクリプトを、このディレクトリ内の新規ファイル（`_tuist` ）にコピーしてください：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`および oh-my-zsh`
を使用しない場合、補完スクリプトのパスを関数パスに追加し、補完スクリプトの自動読み込みを有効にする必要があります。まず、以下の行を`~/.zshrc`
に追加してください：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion` にディレクトリを作成し、コンプリートスクリプトを新しいディレクトリにコピーします。ファイル名は`_tuist`
とします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

[bash-completion](https://github.com/scop/bash-completion)がインストールされている場合、新しい補完スクリプトを以下のファイルにコピーするだけで利用可能です：`/usr/local/etc/bash_completion.d/_tuist`

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completionが有効でない場合、補完スクリプトを直接ソースする必要があります。スクリプトを` や~/.bash_completions/（`
）などのディレクトリにコピーし、次に` や~/.bash_profile（` ）、あるいは` や~/.bashrc（` ）に以下の行を追加してください：

```bash
source ~/.bash_completions/example.bash
```

#### 魚{#fish}

[fish
shell](https://fishshell.com)を使用する場合、新しい補完スクリプトを以下にコピーできます：`~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
