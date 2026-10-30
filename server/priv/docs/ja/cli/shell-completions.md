---
{
  "title": "シェルの補完",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist コマンドを自動補完するためのシェル設定方法を学びます。"
}
---
# シェルの補完機能

Tuistを**グローバルにインストール**している場合（例：Homebrew経由）、BashおよびZsh用のシェル補完をインストールして、コマンドやオプションの自動補完を有効にできます。

> [!WARNING]
> **グローバルインストールとは**
>
> グローバルインストールとは、シェルの`$PATH`環境変数で利用可能なインストールのことです。これにより、ターミナル内の任意のディレクトリから`tuist`を実行できます。これはHomebrewでのデフォルトのインストール方法です。


#### Zsh {#zsh}

[oh-my-zsh](https://ohmyz.sh/)がインストールされている場合、補完スクリプトを自動的に読み込むディレクトリ（`.oh-my-zsh/completions`）がすでに存在します。新しい補完スクリプトを、そのディレクトリ内の`_tuist`という名前の新しいファイルにコピーしてください。

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

`oh-my-zsh`を使用しない場合は、関数パスに補完スクリプトのパスを追加し、補完スクリプトの自動読み込みを有効にする必要があります。まず、次の行を`~/.zshrc`に追加してください。

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

次に、`~/.zsh/completion`にディレクトリを作成し、補完スクリプトを新しいディレクトリにコピーします。ここでもファイル名は`_tuist`とします。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

[bash-completion](https://github.com/scop/bash-completion)がインストールされている場合は、新しい補完スクリプトをファイル`/usr/local/etc/bash_completion.d/_tuist`にコピーするだけです。

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

bash-completionを使用しない場合は、補完スクリプトを直接sourceする必要があります。`~/.bash_completions/`などのディレクトリにコピーし、その後、次の行を`~/.bash_profile`または`~/.bashrc`に追加してください。

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

[fish shell](https://fishshell.com)を使用している場合は、新しい補完スクリプトを`~/.config/fish/completions/tuist.fish`にコピーできます。

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
