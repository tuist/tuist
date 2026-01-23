---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

若您已通过全局安装（如通过Homebrew）获取Tuist**** ，可为Bash和Zsh安装命令补全功能，实现命令与选项的自动补全。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全局安装是指安装在终端环境变量（`$PATH` ）中的软件。这意味着您可在终端任意目录运行：`tuist` 此为Homebrew的默认安装方式。
<!-- -->
:::

#### Zsh{#zsh}

若已安装[oh-my-zsh](https://ohmyz.sh/)，则自动加载补全脚本的目录已存在——`.oh-my-zsh/completions`
。将新补全脚本复制到该目录下的新文件中，命名为`_tuist` ：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

若未安装`（即oh-my-zsh）` ，需将补全脚本路径添加至函数路径，并启用补全脚本自动加载功能。首先在` 或~/.zshrc中添加以下内容` ：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下来，在以下路径创建目录：`~/.zsh/completion` 并将补全脚本复制到新目录中，同样命名为：`_tuist`

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

若已安装[bash-completion](https://github.com/scop/bash-completion)，可将新补全脚本复制至文件：`/usr/local/etc/bash_completion.d/_tuist`

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

```若未启用bash补全功能，需直接加载补全脚本。请将其复制至指定目录（如` 或~/.bash_completions/），随后在`
、~/.bash_profile或` 、~/.bashrc中添加以下内容：

```bash
source ~/.bash_completions/example.bash
```

#### 鱼{#fish}

若使用[fish
shell](https://fishshell.com)，可将新补全脚本复制至：`~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
