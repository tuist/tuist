---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

如果您在**全局安装了 Tuist** （例如通过 Homebrew），则可以为 Bash 和 Zsh 安装 shell
completions，以自动完成命令和选项。

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
全局安装是指在 shell 的`$PATH` 环境变量中可用的安装。这意味着你可以在终端的任何目录下运行`tuist` 。这是 Homebrew
的默认安装方法。
<!-- -->
:::

#### Zsh{#zsh}

如果您安装了 [oh-my-zsh](https://ohmyz.sh/) ，您已经有一个自动加载完成脚本的目录
-`.oh-my-zsh/completions` 。将新的完成脚本复制到该目录中名为`_tuist` 的新文件中：

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

如果没有`oh-my-zsh` ，则需要在函数路径中添加完成脚本的路径，并开启完成脚本自动加载功能。首先，在`~/.zshrc` 中添加这几行：

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

接下来，在`~/.zsh/completion` 下创建一个目录，并将完成脚本复制到新目录中，同样复制到名为`_tuist` 的文件中。

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### 巴什{#bash}

如果已经安装了
[bash-completion](https://github.com/scop/bash-completion)，可以直接将新的完成脚本复制到文件`/usr/local/etc/bash_completion.d/_tuist`
：

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

如果没有 bash-completion，则需要直接获取补全脚本。将其复制到`~/.bash_completions/`
等目录，然后在`~/.bash_profile` 或`~/.bashrc` 中添加以下一行：

```bash
source ~/.bash_completions/example.bash
```

#### 鱼类{#fish}

如果使用 [fish
shell](https://fishshell.com)，可以将新的完成脚本复制到`~/.config/fish/completions/tuist.fish`
：

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
