---
{
  "title": "Shell 自動補全",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解如何設定你的 Shell，以自動補全 Tuist 指令。"
}
---
# Shell 自動補全 {#shell-completions}

如果你已**全局安裝** Tuist（例如透過 Homebrew），你可以為 Zsh、Bash 同 Fish 安裝 Shell 自動補全，以便自動完成指令同選項。

> [!NOTE]
> **乜嘢係全局安裝**
>
> 全局安裝指安裝位置已加入你 Shell 嘅 `$PATH` 環境變數。這意味著你可以在終端機嘅任何目錄執行 `tuist`。呢個係 Homebrew 嘅預設安裝方法。


## Zsh {#zsh}

如果你已安裝 [oh-my-zsh](https://ohmyz.sh/)，你已經有一個會自動載入補全腳本嘅目錄 — `.oh-my-zsh/completions`。將你嘅新補全腳本複製到該目錄中一個名為 `_tuist` 嘅新檔案：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果冇 `oh-my-zsh`，你需要將補全腳本嘅路徑加入函數路徑，並開啟補全腳本自動載入功能。首先，將以下幾行加入 `~/.zshrc`：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下來，於 `~/.zsh/completion` 建立一個目錄，並將補全腳本複製到新目錄，同樣儲存為名為 `_tuist` 嘅檔案。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

## Bash {#bash}

如果你已安裝 [bash-completion](https://github.com/scop/bash-completion)，你可以直接將新嘅補全腳本複製到 bash-completion 嘅目錄：

```bash
tuist --generate-completion-script bash > "$(brew --prefix)/etc/bash_completion.d/_tuist"
```

如果冇 bash-completion，你需要直接 source 補全腳本。將其寫入例如 `~/.bash_completions/` 嘅目錄：

```bash
mkdir -p ~/.bash_completions
tuist --generate-completion-script bash > ~/.bash_completions/tuist.bash
```

然後將以下一行加入 `~/.bash_profile` 或 `~/.bashrc`：

```bash
source ~/.bash_completions/tuist.bash
```

## Fish {#fish}

如果你使用 [fish shell](https://fishshell.com)，你可以將新嘅補全腳本複製到 `~/.config/fish/completions/tuist.fish`：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
