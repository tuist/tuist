---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Uzupełnienia komend powłoki

Jeśli masz globalnie zainstalowany Tuist **** (np. poprzez Homebrew), możesz
zainstalować uzupełnienia powłoki dla Bash i Zsh, aby automatycznie uzupełniać
polecenia i opcje.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Instalacja globalna to instalacja dostępna w zmiennej środowiskowej powłoki
`$PATH`. Oznacza to, że możesz uruchomić `tuist` z dowolnego katalogu w
terminalu. Jest to domyślna metoda instalacji dla Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

Jeśli masz zainstalowany [oh-my-zsh](https://ohmyz.sh/), masz już katalog
automatycznie ładowanych skryptów uzupełniania — `.oh-my-zsh/completions`.
Skopiuj nowy skrypt uzupełniania do nowego pliku w tym katalogu o nazwie
`_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Bez `oh-my-zsh` musisz dodać ścieżkę do skryptów uzupełniających do ścieżki
funkcji i włączyć automatyczne ładowanie skryptów uzupełniających. Najpierw
dodaj te linie do `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Następnie utwórz katalog w `~/.zsh/completion` i skopiuj skrypt uzupełniania do
nowego katalogu, ponownie do pliku o nazwie `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Jeśli masz zainstalowany
[bash-completion](https://github.com/scop/bash-completion), możesz po prostu
skopiować nowy skrypt uzupełniający do pliku
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Bez funkcji bash-completion konieczne będzie bezpośrednie uruchomienie skryptu
uzupełniającego. Skopiuj go do katalogu, np. `~/.bash_completions/`, a następnie
dodaj następujący wiersz do pliku `~/.bash_profile` lub `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Ryba {#fish}

Jeśli używasz [fish shell](https://fishshell.com), możesz skopiować swój nowy
skrypt uzupełniania do `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
