---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Установите Tuist {#install-tuist}

Tuist CLI состоит из исполняемого файла, динамических фреймворков и набора
ресурсов (например, шаблонов). Хотя вы можете вручную собрать Tuist из [исходных
текстов](https://github.com/tuist/tuist), **мы рекомендуем использовать один из
следующих методов установки для обеспечения корректной установки.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info Mise - это рекомендуемая альтернатива [Homebrew](https://brew.sh), если
вы - команда или организация, которой необходимо обеспечить детерминированные
версии инструментов в различных средах. :::

Вы можете установить Tuist с помощью любой из следующих команд:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Обратите внимание, что в отличие от таких инструментов, как Homebrew, которые
устанавливают и активируют одну версию инструмента глобально, **Mise требует
активации версии** либо глобально, либо с привязкой к проекту. Это делается
путем выполнения команды `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Домашнее пиво</a> {#recommended-homebrew}

Вы можете установить Tuist, используя [Homebrew](https://brew.sh) и [наши
формулы](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: совет ПРОВЕРКА АВТОМАТИЧНОСТИ БИНАРИЙ Вы можете убедиться, что бинарные
файлы вашей установки были собраны нами, выполнив следующую команду, которая
проверяет, является ли команда сертификата `U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
:::
