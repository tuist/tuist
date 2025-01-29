---
title: Установка Tuist
titleTemplate: :title · Начало · Руководства · Tuist
description: Узнайте, как установить Tuist в вашей среде.
---

# Установка Tuist {#install-tuist}

Tuist CLI состоит из исполняемого файла, динамических фреймворков и набора ресурсов (например, шаблонов). Хотя вы можете самостоятельно собрать Tuist из  [исходников](https://github.com/tuist/tuist,  **мы рекомендуем использовать один из следующих методов установки.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::info
Mise является рекомендуемой альтернативой [Homebrew](https://brew.sh), если вы работаете в команде или организации, которая должна обеспечить детерминированные версии инструментов в различных средах.
:::

Вы можете установить Tuist с помощью любой из следующих команд:

```bash
mise install tuist            # Установить текущую версию, указанную в .tool-versions/.mise.toml
mise install tuist@x.y.z      # Установить версию с указанным номером
mise install tuist@3          # Установить версию с нестрогим номером
```

Обратите внимание, что в отличие от инструментов, таких как Homebrew, устанавливающих и активирующих одну версию инструмента глобально, **Mise требует активации версии** либо глобально, либо в рамках проекта. Это делается выполнением `mise use`:

```bash
mise use tuist@x.y.z          # Использовать tuist версии x.y.z в текущей директории
mise use tuist@latest         # Использовать tuist последней версии в текущей директории
mise use -g tuist@x.y.z       # Использовать tuist версии x.y.z глобально
mise use -g tuist@system      # Использовать системный tuist глобально
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Вы можете установить Tuist, используя [Homebrew](https://brew.sh) и [наши формулы](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

:::tip ПОДТВЕРЖДЕНИЕ ПОДЛИННОСТИ БИНАРНЫХ ФАЙЛОВ

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```

:::

### Автодополнения в командной оболочки {#shell-completions}

Если у вас Tuist **установлен глобально** (например, через Homebrew),
вы можете установить автодополнения для Bash и Zsh для автоматического заполнения команд и опций.

:::warning ЧТО ЕСТЬ ГЛОБАЛЬНАЯ УСТАНОВКА
Глобальная установка — это установка, которая доступна в переменной среды `$PATH` в вашей командной оболочке. Это означает, что вы можете выполнить `tuist` из любой директории в вашем терминале. This is the default installation method for Homebrew.
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
