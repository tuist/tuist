---
{
  "title": "CLI",
  "titleTemplate": ":title · Код · Участники · Tuist",
  "description": "Внесите вклад в разработку CLI Tuist."
}
---
# CLI {#cli}

Исходный код: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) и [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Для чего это нужно {#what-it-is-for}

CLI — ядро Tuist. Он отвечает за генерацию проектов, автоматизацию рабочих процессов (тестирование, запуск, построение графа зависимостей и инспекцию) и предоставляет интерфейс к серверу Tuist для таких возможностей, как аутентификация, кэширование, аналитика, превью, реестр и выборочное тестирование.

## Как внести вклад {#how-to-contribute}

### Требования {#requirements}

- macOS 14.0+
- Xcode 26+

### Локальная настройка {#set-up-locally}

- Клонируйте репозиторий: `git clone git@github.com:tuist/tuist.git`
- Установите Mise с помощью [официального скрипта установки](https://mise.jdx.dev/getting-started.html) (не через Homebrew) и выполните `mise install`
- Установите зависимости Tuist: `tuist install`
- Сгенерируйте рабочее пространство: `tuist generate`

Сгенерированный проект открывается автоматически. Если вам понадобится открыть его позже, выполните `open Tuist.xcworkspace`.

> [!NOTE]
> **Xed .**
>
> Если вы попытаетесь открыть проект с помощью `xed .`, откроется пакет, а не сгенерированное Tuist рабочее пространство. Используйте `Tuist.xcworkspace`.


### Запуск Tuist {#run-tuist}

#### Из Xcode {#from-xcode}

Отредактируйте схему `tuist` и задайте аргументы, например `generate --no-open`. Установите рабочий каталог в корень проекта (или используйте `--path`).

> [!WARNING]
> **Компиляция ProjectDescription**
>
> CLI зависит от сборки `ProjectDescription`. Если запуск не удается, сначала соберите схему `Tuist-Workspace`.


#### Из терминала {#from-the-terminal}

Сначала сгенерируйте рабочее пространство:

```bash
tuist generate --no-open
```

Затем соберите исполняемый файл `tuist` с помощью Xcode и запустите его из DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

Или через Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
