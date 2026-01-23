---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Источник:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
и
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Для чего это нужно {#what-it-is-for}

CLI — это сердце Tuist. Он обрабатывает генерацию проектов, автоматизирует
рабочие процессы (тестирование, запуск, построение графиков и проверка) и
предоставляет интерфейс к серверу Tuist для таких функций, как аутентификация,
кэширование, аналитика, предварительный просмотр, реестр и выборочное
тестирование.

## Как внести свой вклад {#how-to-contribute}

### Требования {#requirements}

- macOS 14.0+
- Xcode 26+

### Настройте локально {#set-up-locally}

- Клонируйте репозиторий, выполнив команду `git clone
  git@github.com:tuist/tuist.git`
- Установите Mise с помощью [их официального скрипта
  установки](https://mise.jdx.dev/getting-started.html) (не Homebrew) и
  запустите `mise install`
- Установите зависимости Tuist: `tuist install`
- Создайте рабочую область: `tuist generate`

Сгенерированный проект открывается автоматически. Если вам нужно будет открыть
его позже, запустите `open Tuist.xcworkspace`.

::: info XED .
<!-- -->
Если вы попытаетесь открыть проект с помощью `xed .`, откроется пакет, а не
рабочая область, сгенерированная Tuist. Используйте `Tuist.xcworkspace`.
<!-- -->
:::

### Запуск Tuist {#run-tuist}

#### Из Xcode {#from-xcode}

Отредактируйте файл `tuist` scheme и установите такие аргументы, как `generate
--no-open`. Установите рабочий каталог в корневой каталог проекта (или
используйте `--path`).

::: warning PROJECT DESCRIPTION COMPILATION
<!-- -->
CLI зависит от сборки проекта `ProjectDescription`. Если он не запускается,
сначала соберите схему `Tuist-Workspace`.
<!-- -->
:::

#### Из терминала {#from-the-terminal}

Сначала создайте рабочую область:

```bash
tuist generate --no-open
```

Затем скомпилируйте исполняемый файл `tuist` с помощью Xcode и запустите его из
DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

Или через Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
