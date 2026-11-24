---
{
  "title": "Shell 自動補全",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解如何設定你的 Shell，以自動補全 Tuist 指令。"
}
---
# Shell 自動補完 {#shell-completions}

如果你已**全域安裝** Tuist（例如透過 Homebrew），你可以為 Zsh、Bash 和 Fish 安裝 Shell 自動補完，以自動補全指令和選項。

> [!NOTE]
> **甚麼是全域安裝**
>
> 全域安裝指安裝位置位於你 Shell 的 `$PATH` 環境變數中。這表示你可以在終端機的任何目錄執行 `tuist`。這是 Homebrew 的預設安裝方式。


## Zsh {#zsh}

如果你已安裝 [oh-my-zsh](https://ohmyz.sh/)，你已經有一個會自動載入補完腳本的目錄 — `.oh-my-zsh/completions`。將新的補完腳本複製到該目錄中一個名為 `_tuist` 的新檔案：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果沒有 `oh-my-zsh`，你需要將補完腳本的路徑加入函式路徑，並啟用補完腳本自動載入。首先，將以下幾行加入 `~/.zshrc`：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接著，在 `~/.zsh/completion` 建立目錄，並將補完腳本複製到新目錄中，同樣命名為 `_tuist`。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

如果你已安裝 [bash-completion](https://github.com/scop/bash-completion)，你可以直接將新的補完腳本複製到 bash-completion 的目錄：

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

如果沒有 bash-completion，你需要直接 source 補完腳本。將其寫入例如 `~/.bash_completions/` 的目錄：

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

然後將以下這一行加入 `~/.bash_profile` 或 `~/.bashrc`：

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

如果你使用 [fish shell](https://fishshell.com)，你可以將新的補完腳本複製到 `~/.config/fish/completions/tuist.fish`：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
