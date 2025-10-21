---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Установка Tuist {#install-tuist}

CLI Tuist состоит из исполняемого файла, динамических фреймворков и набора
ресурсов (например, шаблонов). Хотя вы можете собрать Tuist вручную из
[исходного кода](https://github.com/tuist/tuist), **мы рекомендуем использовать
один из следующих способов установки, чтобы гарантировать корректную
установку.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
Mise – рекомендуемая альтернатива [Homebrew](https://brew.sh) для команд и
организаций, которым нужно обеспечивать детерминированные версии инструментов в
разных средах.
<!-- -->
:::

Установить Tuist можно с помощью одной из следующих команд:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Обратите внимание, что в отличие от Homebrew, который устанавливает и активирует
одну версию инструмента глобально, **Mise требует активации версии** – либо
глобально, либо в рамках конкретного проекта. Это делается с помощью команды
`mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Вы можете установить Tuist с помощью [Homebrew](https://brew.sh) и [наших
формул](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip ПРОВЕРКА ПОДЛИННОСТИ БИНАРНЫХ ФАЙЛОВ
<!-- -->
Вы можете убедиться, что бинарные файлы вышей установки было собраны нами,
выполнив следующую команду, которая проверяет, что идентификатор команды в
сертификате – `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
