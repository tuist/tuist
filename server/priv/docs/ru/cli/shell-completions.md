---
{
  "title": "Автодополнение в оболочке",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Узнайте, как настроить оболочку для автодополнения команд Tuist."
}
---
# Автодополнение в оболочке

Если Tuist **установлен глобально** (например, через Homebrew), вы можете установить автодополнение для Bash и Zsh, чтобы автоматически дополнять команды и параметры.

> [!WARNING]
> **Что такое глобальная установка**
>
> Глобальная установка — это установка, доступная в переменной окружения `$PATH` вашей оболочки. Это означает, что вы можете запускать `tuist` из любого каталога в терминале. Это стандартный способ установки для Homebrew.


#### Zsh {#zsh}

Если у вас установлен [oh-my-zsh](https://ohmyz.sh/), у вас уже есть каталог с автоматически загружаемыми скриптами автодополнения — `.oh-my-zsh/completions`. Скопируйте новый скрипт автодополнения в новый файл в этом каталоге с именем `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Без `oh-my-zsh` вам нужно добавить путь к скриптам автодополнения в путь функций и включить автоматическую загрузку скриптов автодополнения. Сначала добавьте эти строки в `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Затем создайте каталог `~/.zsh/completion` и скопируйте скрипт автодополнения в новый каталог, снова в файл с именем `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Если у вас установлен [bash-completion](https://github.com/scop/bash-completion), вы можете просто скопировать новый скрипт автодополнения в файл `/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

Без bash-completion вам нужно будет напрямую подключить скрипт автодополнения. Скопируйте его в каталог, например `~/.bash_completions/`, а затем добавьте следующую строку в `~/.bash_profile` или `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Fish {#fish}

Если вы используете [fish shell](https://fishshell.com), вы можете скопировать новый скрипт автодополнения в `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
