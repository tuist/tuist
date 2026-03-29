---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell 自動完成

若您已透過** 將 Tuist**安裝為系統層級套件（例如透過 Homebrew），即可安裝適用於 Bash 和 Zsh
的殼層自動完成功能，以自動補全命令與選項。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全域安裝是指可在您的 shell 環境變數`$PATH` 中使用的安裝。這表示您可以在終端機的任何目錄中執行`tuist` 。這是 Homebrew
的預設安裝方式。
<!-- -->
:::

#### Zsh{#zsh}

若您已安裝 [oh-my-zsh](https://ohmyz.sh/)，系統中已存在一個用於自動載入補全腳本的目錄
—`.oh-my-zsh/completions` 。請將您的新補全腳本複製到該目錄中，並建立名為`_tuist` 的新檔案：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

若未安裝`oh-my-zsh` ，您需將完成腳本的路徑加入函式路徑中，並啟用完成腳本的自動載入功能。首先，請將以下幾行加入`~/.zshrc` ：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接著，在`~/.zsh/completion` 建立一個目錄，並將完成腳本複製到新目錄中，同樣存入名為`_tuist` 的檔案。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

若您已安裝
[bash-completion](https://github.com/scop/bash-completion)，只需將新的補全腳本複製到檔案`/usr/local/etc/bash_completion.d/_tuist`
：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

若未啟用 bash-completion，您需要直接載入完成腳本。請將其複製到目錄中，例如`~/.bash_completions/`
，然後在`~/.bash_profile` 或`~/.bashrc` 中加入以下這行：

```bash
source ~/.bash_completions/example.bash
```

#### Fish{#fish}

若您使用 [fish
shell](https://fishshell.com)，可將新的自動完成腳本複製至`~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
