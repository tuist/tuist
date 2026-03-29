---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

如果您已全局安装 Tuist**** （例如通过 Homebrew），则可以安装 Bash 和 Zsh 的 shell 补全功能，以实现命令和选项的自动补全。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全局安装是指可在 shell 的`$PATH` 环境变量中访问的安装。这意味着您可以在终端的任何目录下运行`tuist` 。这是 Homebrew
的默认安装方式。
<!-- -->
:::

#### Zsh{#zsh}

如果您已安装 [oh-my-zsh](https://ohmyz.sh/)，系统中已存在一个用于自动加载补全脚本的目录
—`.oh-my-zsh/completions` 。请将您的新补全脚本复制到该目录下，并将其命名为`_tuist` ：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果没有`oh-my-zsh` ，您需要将补全脚本的路径添加到函数路径中，并启用补全脚本的自动加载。首先，将以下几行添加到`~/.zshrc` 中：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下来，在`~/.zsh/completion` 路径下创建一个目录，并将补全脚本复制到该新目录中，同样保存为名为`_tuist` 的文件。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash{#bash}

如果您已安装
[bash-completion](https://github.com/scop/bash-completion)，只需将新的补全脚本复制到文件`/usr/local/etc/bash_completion.d/_tuist`
中即可：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

如果没有 bash-completion，您需要直接加载补全脚本。将其复制到`~/.bash_completions/`
等目录中，然后在`~/.bash_profile` 或`~/.bashrc` 中添加以下行：

```bash
source ~/.bash_completions/example.bash
```

#### Fish{#fish}

如果你使用 [fish
shell](https://fishshell.com)，可以将新的补全脚本复制到`~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
