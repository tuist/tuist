---
{
  "title": "Shell completions",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to configure your shell to auto-complete Tuist commands."
}
---
# Автозавершения Shell

Если у вас есть глобальная установка Tuist **** (например, через Homebrew), вы
можете установить дополнения оболочки для Bash и Zsh для автозаполнения команд и
опций.

::: warning WHAT IS A GLOBAL INSTALLATION
<!-- -->
Глобальная установка - это установка, которая доступна в переменной окружения
вашей оболочки `$PATH`. Это означает, что вы можете запустить `tuist` из любой
директории в вашем терминале. Это метод установки по умолчанию для Homebrew.
<!-- -->
:::

#### Zsh {#zsh}

Если у вас установлен [oh-my-zsh](https://ohmyz.sh/), у вас уже есть каталог
автоматически загружающихся скриптов завершения - `.oh-my-zsh/completions`.
Скопируйте свой новый сценарий завершения в новый файл в этом каталоге под
названием `_tuist`:

```bash
tuist --generate-completion-script > ~/.oh-my-zsh/completions/_tuist
```

Без `oh-my-zsh` вам придется добавить путь для скриптов завершения в путь
функций и включить автозагрузку скриптов завершения. Сначала добавьте эти строки
в `~/.zshrc`:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -U compinit
compinit
```

Затем создайте каталог `~/.zsh/completion` и скопируйте сценарий завершения в
новый каталог, опять же в файл с именем `_tuist`.

```bash
tuist --generate-completion-script > ~/.zsh/completion/_tuist
```

#### Bash {#bash}

Если у вас установлен
[bash-completion](https://github.com/scop/bash-completion), вы можете просто
скопировать ваш новый скрипт завершения в файл
`/usr/local/etc/bash_completion.d/_tuist`:

```bash
tuist --generate-completion-script > /usr/local/etc/bash_completion.d/_tuist
```

При отсутствии bash-completion вам придется использовать скрипт завершения
напрямую. Скопируйте его в каталог, например `~/.bash_completions/`, а затем
добавьте следующую строку в `~/.bash_profile` или `~/.bashrc`:

```bash
source ~/.bash_completions/example.bash
```

#### Рыба {#fish}

Если вы используете [fish shell](https://fishshell.com), вы можете скопировать
новый скрипт завершения в `~/.config/fish/completions/tuist.fish`:

```bash
mkdir -p ~/.config/fish/completions
tuist --generate-completion-script > ~/.config/fish/completions/tuist.fish
```
