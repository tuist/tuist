---
title: Setting up your shell
slug: '/guides/shell-autocompletion'
description: 'To ease usage of tuist, learn how you can generate autocompletions for your shell'
---

Tuist supports autocompletion, so just by hitting a tab your shell can give you hints what you can type next.
This does not come out the box as it is dependent on your shell, so follow the appropriate set of instructions below.

### Generate completion scripts

The `tuist --generate-completion-script` command will print the completion script to the standard output.

### Installing Zsh Completions

If you have [`oh-my-zsh`](https://ohmyz.sh) installed, you already have a directory of automatically loading completion scripts — `.oh-my-zsh/completions`. Copy your new completion script to a new file in that directory called `_tuist`:

```sh
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Without `oh-my-zsh`, you'll need to add a path for completion scripts to your function path, and turn on completion script autoloading. First, add these lines to `~/.zshrc`:

```sh
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Next, create a directory at `~/.zsh/completion` and copy the completion script to the new directory, again into a file called `_tuist`.

```sh
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

### Installing Bash Completions

If you have [`bash-completion`](https://github.com/scop/bash-completion) installed, you can just copy your new completion script to file `/usr/local/etc/bash_completion.d/_tuist`.

```sh
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Without `bash-completion`, you'll need to source the completion script directly. Copy it to a directory such as `~/.bash_completions/`, and then add the following line to `~/.bash_profile` or `~/.bashrc`:

```sh
source ~/.bash_completions/example.bash
```

To learn more about how completions work, we refer you to [Swift Argument Parser documentation](https://github.com/apple/swift-argument-parser/blob/280700d361c1b3af6e2345f5e24f67fa9450bec6/Documentation/07%20Completion%20Scripts.md).
