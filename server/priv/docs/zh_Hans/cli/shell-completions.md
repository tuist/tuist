---
{
  "title": "Shell 自动补全",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解如何配置 Shell 以自动补全 Tuist 命令。"
}
---
# Shell 自动补全

如果你已**全局安装** Tuist（例如通过 Homebrew），你可以为 Bash 和 Zsh 安装 Shell 自动补全，以自动补全命令和选项。

> [!WARNING]
> **什么是全局安装**
>
> 全局安装是指安装在你的 Shell `$PATH` 环境变量中的安装方式。这意味着你可以在终端的任何目录下运行 `tuist`。这是 Homebrew 的默认安装方法。


#### Zsh {#zsh}

如果你已安装 [oh-my-zsh](https://ohmyz.sh/)，你已经拥有一个自动加载补全脚本的目录——`.oh-my-zsh/completions`。将你的新补全脚本复制到该目录中一个名为 `_tuist` 的新文件中：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果没有 `oh-my-zsh`，你需要将补全脚本的路径添加到你的函数路径中，并启用补全脚本的自动加载。首先，将这些行添加到 `~/.zshrc`：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下来，在 `~/.zsh/completion` 创建一个目录，并将补全脚本复制到新目录中，同样保存为名为 `_tuist` 的文件。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

如果你已安装 [bash-completion](https://github.com/scop/bash-completion)，你可以直接将新的补全脚本复制到文件 `/usr/local/etc/bash_completion.d/_tuist`：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

如果没有 bash-completion，你需要直接 source 补全脚本。将其复制到一个目录（如 `~/.bash_completions/`），然后将以下行添加到 `~/.bash_profile` 或 `~/.bashrc`：

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

如果你使用 [fish shell](https://fishshell.com)，你可以将新的补全脚本复制到 `~/.config/fish/completions/tuist.fish`：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
