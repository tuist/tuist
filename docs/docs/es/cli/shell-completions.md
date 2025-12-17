---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Shell completions

If you have Tuist **globally installed** (e.g., via Homebrew), you can install
shell completions for Bash and Zsh to autocomplete commands and options.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
A global installation is an installation that's available in your shell's
`$PATH` environment variable. This means you can run `tuist` from any directory
in your terminal. This is the default installation method for Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

If you have [oh-my-zsh](https://ohmyz.sh/) installed, you already have a
directory of automatically loading completion scripts —
`.oh-my-zsh/completions`. Copy your new completion script to a new file in that
directory called `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Without `oh-my-zsh`, you'll need to add a path for completion scripts to your
function path, and turn on completion script autoloading. First, add these lines
to `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Next, create a directory at `~/.zsh/completion` and copy the completion script
to the new directory, again into a file called `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

If you have [bash-completion](https://github.com/scop/bash-completion)
installed, you can just copy your new completion script to file
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Without bash-completion, you'll need to source the completion script directly.
Copy it to a directory such as `~/.bash_completions/`, and then add the
following line to `~/.bash_profile` or `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

If you use [fish shell](https://fishshell.com), you can copy your new completion
script to `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
