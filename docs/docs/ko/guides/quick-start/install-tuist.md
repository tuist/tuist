---
title: Install Tuist
description: Learn how to install Tuist in your environment.
---

# Install Tuist

The Tuist CLI consists of an executable, dynamic frameworks, and a set of resources (for example, templates). Although you could manually build Tuist from [the sources](https://github.com/tuist/tuist), **we recommend using one of the following installation methods to ensure a valid installation.**

### Recommended: [Mise](https://github.com/jdx/mise)

Tuist defaults to [Mise](https://github.com/jdx/mise) as a tool to deterministically manage and activate versions of Tuist.
If you don't have it installed on your system,
you can use any of these [installation methods](https://mise.jdx.dev/getting-started.html).
Remember to add the suggested line to your shell, which will ensure the right version is activated when you choose a Tuist project directory in your terminal session.

::: info
Mise is recommended over alternatives like [Homebrew](https://brew.sh) because it supports scoping and activating versions to directories, ensuring every environment uses the same version of Tuist deterministically.
:::

Once installed, you can install Tuist through any of the following commands:


```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Note that unlike tools like Homebrew, which install and activate a single version of the tool globally, **Mise requires the activation of a version** either globally or scoped to a project. This is done by running `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### Alternative: [Homebrew](https://brew.sh)

If version pinning across environments is not a concern for you,
you can install Tuist using [Homebrew](https://brew.sh) and [our formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

### Shell completions

If you have Tuist **globally installed**,
you can install shell completions for Bash and Zsh to autocomplete commands and options.

::: warning What is a global installation
A global installation is an installation that's available in your shell's `$PATH` environment variable. This means you can run `tuist` from any directory in your terminal. This is the default installation method for Homebrew.
:::

#### Zsh

If you have [oh-my-zsh](https://ohmyz.sh/) installed, you already have a directory of automatically loading completion scripts — `.oh-my-zsh/completions`. Copy your new completion script to a new file in that directory called `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Without `oh-my-zsh`, you'll need to add a path for completion scripts to your function path, and turn on completion script autoloading. First, add these lines to `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Next, create a directory at `~/.zsh/completion` and copy the completion script to the new directory, again into a file called `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash

If you have [bash-completion](https://github.com/scop/bash-completion) installed, you can just copy your new completion script to file `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Without bash-completion, you'll need to source the completion script directly. Copy it to a directory such as `~/.bash_completions/`, and then add the following line to `~/.bash_profile` or `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```