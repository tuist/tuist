---
title: Install Tuist
titleTemplate: :title · Quick-start · Guides · Tuist
description: Learn how to install Tuist in your environment.
---

# Install Tuist {#install-tuist}

The Tuist CLI consists of an executable, dynamic frameworks, and a set of resources (for example, templates). Although you could manually build Tuist from [the sources](https://github.com/tuist/tuist), **we recommend using one of the following installation methods to ensure a valid installation.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
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

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
You can verify that your installation's binaries have been built by us by running the following command, which checks if the certificate's team is `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
:::

### Shell completions {#shell-completions}

If you have Tuist **globally installed** (e.g., via Homebrew),
you can install shell completions for Bash and Zsh to autocomplete commands and options.

::: warning WHAT IS A GLOBAL INSTALLATION
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

#### Fish {#fish}

If you use [fish shell](https://fishshell.com), you can copy your new completion script to `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
