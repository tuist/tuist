---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell 自動補全

** 若您已透過 Homebrew 等管道全域安裝 Tuist 工具（指令：`**`），可進一步安裝 Bash 與 Zsh
的殼層補全功能，實現指令與選項的自動完成。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全域安裝是指安裝後會出現在您的殼層環境變數中：`$PATH` 這意味著您可在終端機的任何目錄執行：`tuist` 此為 Homebrew 的預設安裝方式。
<!-- -->
:::

#### Zsh{#zsh}

若已安裝 [oh-my-zsh](https://ohmyz.sh/)，系統會自動建立載入補全腳本的目錄：`.oh-my-zsh/completions`
請將新補全腳本複製至該目錄下的新檔案：`_tuist`

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

若未安裝 ``` 或 `oh-my-zsh`（參見` ），您需將補全腳本路徑加入函數路徑，並啟用補全腳本自動載入功能。首先在 ``` 或
`~/.zshrc`（參見` ）加入以下設定：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接著在以下路徑建立目錄：`~/.zsh/completion` 將補全腳本複製至新目錄，並命名為：`_tuist`

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

若已安裝
[bash-completion](https://github.com/scop/bash-completion)，可直接將新完成腳本複製至檔案：`/usr/local/etc/bash_completion.d/_tuist`

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

若未啟用 bash 自動補全功能，需直接載入補全腳本。請將腳本複製至指定目錄（例如：`~/.bash_completions/`
），並在以下檔案新增下列行：`~/.bash_profile` 或`~/.bashrc` ：

```bash
source ~/.bash_completions/example.bash
```

#### 魚{#fish}

若使用 [fish shell]{1]，可將新完成腳本複製至：`~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
