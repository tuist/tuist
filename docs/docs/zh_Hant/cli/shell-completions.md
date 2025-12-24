---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# 蜆殼完工

如果您有 Tuist**全局安裝** (例如透過 Homebrew)，您可以為 Bash 和 Zsh 安裝 shell
completions，以自動完成指令和選項。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全局安裝是指在您 shell 的`$PATH` 環境變數中可用的安裝。這表示您可以從終端機的任何目錄執行`tuist` 。這是 Homebrew
的預設安裝方式。
<!-- -->
:::

#### Zsh{#zsh}

如果您已經安裝 [oh-my-zsh](https://ohmyz.sh/) ，您已經有一個自動載入完成指令碼的目錄
-`.oh-my-zsh/completions` 。將您的新完成指令碼複製到該目錄中的新檔案，名稱為`_tuist` ：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果沒有`oh-my-zsh` ，您需要在函式路徑中加入完成指令碼路徑，並開啟完成指令碼自動載入。首先，將這些行加入`~/.zshrc` ：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下來，在`~/.zsh/completion` 建立一個目錄，然後將完成指令碼複製到新目錄，同樣複製到名為`_tuist` 的檔案中。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### 巴什{#bash}

如果您已經安裝
[bash-completion](https://github.com/scop/bash-completion)，您可以直接將新的完成腳本複製到檔案`/usr/local/etc/bash_completion.d/_tuist`
：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

如果沒有 bash-completion，您需要直接取得完成腳本的原始碼。將它複製到一個目錄，例如`~/.bash_completions/`
，然後將下列一行加入`~/.bash_profile` 或`~/.bashrc` ：

```bash
source ~/.bash_completions/example.bash
```

#### 魚類{#fish}

如果您使用 [fish
shell](https://fishshell.com)，您可以將新的完成腳本複製到`~/.config/fish/completions/tuist.fish`
：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
