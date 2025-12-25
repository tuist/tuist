---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Uzupełnienia komend powłoki

Jeśli masz globalnie zainstalowany Tuist **** (np. przez Homebrew), możesz
zainstalować uzupełnienia powłoki dla Bash i Zsh, aby automatycznie uzupełniać
polecenia i opcje.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Instalacja globalna to instalacja, która jest dostępna w zmiennej środowiskowej
powłoki `$PATH`. Oznacza to, że można uruchomić `tuist` z dowolnego katalogu w
terminalu. Jest to domyślna metoda instalacji Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

Jeśli masz zainstalowane [oh-my-zsh](https://ohmyz.sh/), masz już katalog
automatycznie ładujących się skryptów uzupełniania - `.oh-my-zsh/completions`.
Skopiuj nowy skrypt uzupełniania do nowego pliku w tym katalogu o nazwie
`_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Bez `oh-my-zsh`, będziesz musiał dodać ścieżkę do skryptów uzupełniania do
ścieżki funkcji i włączyć automatyczne ładowanie skryptów uzupełniania. Najpierw
dodaj te linie do `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Następnie utwórz katalog pod adresem `~/.zsh/completion` i skopiuj skrypt
uzupełniania do nowego katalogu, ponownie do pliku o nazwie `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Jeśli masz zainstalowany
[bash-completion](https://github.com/scop/bash-completion), możesz po prostu
skopiować nowy skrypt uzupełniania do pliku
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Bez bash-completion, będziesz musiał pobrać skrypt uzupełniania bezpośrednio.
Skopiuj go do katalogu takiego jak `~/.bash_completions/`, a następnie dodaj
następującą linię do `~/.bash_profile` lub `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Ryba {#fish}

Jeśli używasz [fish shell](https://fishshell.com), możesz skopiować nowy skrypt
uzupełniania do `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
