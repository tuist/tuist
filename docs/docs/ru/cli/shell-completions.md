---
{
  "title": "Автозавершения Shell",
  "titleTemplate": ":title · Интерфейс командной строки (CLI) · Tuist",
  "description": "Узнайте, как настроить оболочку для автоматического завершения команд Tuist."
}
---
# Автозавершения Shell

Если у вас Tuist **установлен глобально** (например, через Homebrew),
вы можете установить автодополнения для Bash и Zsh для автоматического заполнения команд и опций.

:::warning ЧТО ЕСТЬ ГЛОБАЛЬНАЯ УСТАНОВКА
Глобальная установка — это установка, которая доступна в переменной среды `$PATH` в вашей командной оболочке. Это означает, что вы можете выполнить `tuist` из любой директории в вашем терминале. Это метод установки по умолчанию для Homebrew.
:::

#### Zsh {#zsh}

Если у вас установлен [oh-my-zsh](https://ohmyz.sh/), у вас уже есть директория для скриптов автодополнения — `.oh-my-zsh/completions`. Скопируйте ваш новый скрипт автодополнений в новый файл с именем `_tuist` в ту директорию:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Без `oh-my-zsh`, вам нужно добавить путь до скрипта автодополнений в ваш путь к функциям и включить автозагрузку. Сначала добавьте эти строки в `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Затем создайте каталог в папке `~/.zsh/completion` и скопируйте скрипт автодополнений в эту новую директорию, в файл с именем `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Если у вас установлен [bash-completion](https://github.com/scop/bash-completion), вы можете просто скопировать скрипт автодополнений в файл `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Без bash-completion, вам нужно выполнить `source` для скрипта автодополнений напрямую. Скопируйте скрипт в директорию `~/.bash_completions/` и, затем, добавьте следующую строку в `~/.bash_profile` или `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

Если вы используете [fish оболочку](https://fishshell.com), вы можете скопировать ваш новый скрипт автодополнений в `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
