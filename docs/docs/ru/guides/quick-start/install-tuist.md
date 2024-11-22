---
title: Установка Tuist
titleTemplate: :title · Quick-start · Guides · Tuist
description: Узнайте, как установить Tuist в вашей среде.
---

# Установка Tuist {#install-tuist}

Tuist CLI состоит из исполняемого файла, динамических фреймворков и набора ресурсов (например, шаблонов). Хотя вы можете самостоятельно собрать Tuist из  [исходников](https://github.com/tuist/tuist,  **мы рекомендуем использовать один из следующих методов установки.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::info
Mise is a recommended alternative to [Homebrew](https://brew.sh) if you are a team or organization that needs to ensure deterministic versions of tools across different environments.
:::

You can install Tuist through any of the following commands:

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

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

You can install Tuist using [Homebrew](https://brew.sh) and [our formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

### Shell completions {#shell-completions}

If you have Tuist **globally installed** (e.g., via Homebrew),
you can install shell completions for Bash and Zsh to autocomplete commands and options.

:::warning What is a global installation
A global installation is an installation that's available in your shell's `$PATH` environment variable. This means you can run `tuist` from any directory in your terminal. This is the default installation method for Homebrew.
:::

#### Zsh {#zsh}

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

#### Bash {#bash}

If you have [bash-completion](https://github.com/scop/bash-completion) installed, you can just copy your new completion script to file `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Without bash-completion, you'll need to source the completion script directly. Copy it to a directory such as `~/.bash_completions/`, and then add the following line to `~/.bash_profile` or `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```
