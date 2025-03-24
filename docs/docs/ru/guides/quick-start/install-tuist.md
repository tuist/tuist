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
