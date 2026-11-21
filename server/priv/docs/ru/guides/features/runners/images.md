---
{
  "title": "Образы",
  "titleTemplate": ":title · Исполнители · Возможности · Руководства · Tuist",
  "description": "Что предустановлено на исполнителях Tuist: образы macOS с Xcode, симуляторами и инструментарием Metal, а также образы Ubuntu с Docker и Android SDK."
}
---
# Образы {#images}

Каждая задача Tuist Runners запускается в новой виртуальной машине, загруженной из образа раннера. Ваш <.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> выбирает образ: платформу, версию Xcode на macOS и релиз Ubuntu на Linux. Виртуальная машина удаляется после завершения задачи, поэтому всё, что было установлено в ходе её выполнения, исчезает для следующей задачи.

Образы следуют за раннерами, размещёнными на GitHub, там, где это важно для рабочих процессов: те же пользователь, пути к домашней директории и рабочему пространству, `ImageOS`, `sudo` без пароля и инструменты, которые ожидают большинство рабочих процессов для iOS, macOS и Linux. Они намеренно меньше образов GitHub, поэтому различия перечислены ниже для каждой платформы.

## Выбор образа {#choosing-an-image}

- **Xcode, Apple SDK или симуляторы:** профиль macOS, привязанный к версии Xcode, с которой собирается ваш проект.
- **Docker, сборки и эмуляторы Android или другие инструменты Linux:** профиль Linux на Ubuntu 24.04.
- **Зависимость, которая пока не поддерживает Ubuntu 24.04:** профиль Linux на Ubuntu 22.04.

На macOS вы выбираете Xcode, а не образ: каждая версия Xcode — это отдельный образ, и профиль, привязанный к `26.4.1`, всегда выполняется на образе, собранном с Xcode 26.4.1. Чтобы использовать две версии Xcode, создайте отдельный профиль для каждой.

## macOS {#macos}

Раннеры macOS — это виртуальные машины на базе Apple Silicon (arm64) под управлением **macOS 26 Tahoe**. Имя раннера включает точную версию macOS, например `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, и отображается на этапе **Set up job** задачи.

### Xcode {#xcode}

Каждый образ содержит **ровно одну версию Xcode**, которая выбирается с помощью `xcode-select`, поэтому `xcodebuild` и `xcrun` используют её без дополнительного шага настройки. Это главное отличие от образов, размещённых на GitHub, которые поставляют несколько версий Xcode для переключения во время выполнения задачи. Доступные версии:

{{runner_macos_xcode_versions}}

- **Путь.** Xcode находится по пути `/Applications/Xcode_<version>.app`. Для версии с компонентом патча `/Applications/Xcode_<major>.<minor>.app` указывает на тот же бандл, поэтому `Xcode_26.4.app` разрешается в `Xcode_26.4.1.app`. Рабочие процессы, которые жестко задают путь в стиле GitHub или вызывают `xcode-select -s` с ним, продолжают работать.
- **Симуляторы.** Среда выполнения симуляторов iOS, tvOS, watchOS и visionOS, поставляемая с этой версией Xcode, загружается в образ, поэтому первый вызов `xcodebuild test` не должен их скачивать.
- **Инструментарий Metal.** Начиная с Xcode 26, компилятор Metal не входит в комплект поставки Xcode и должен загружаться отдельно. Каждый образ включает инструментарий Metal, соответствующий его версии Xcode, установленный для пользователя, от имени которого выполняются задачи, поэтому `xcrun metal` и проекты с исходными файлами `.metal` собираются без запуска `xcodebuild -downloadComponent MetalToolchain`.
- **Бета-версии.** Бета-профили (например, `27.3-beta`) отслеживают последнюю бета-версию этого релиза. Когда Apple выпускает новую бета-версию, образ пересобирается, и профиль автоматически переключается на него без изменений с вашей стороны.

### Предустановленное ПО {#macos-software}

- **Инструменты Apple:** Xcode (одна версия на образ), среды выполнения симуляторов, инструментарий Metal, `xcodes`, `xcbeautify`
- **Инструменты Swift и iOS:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Устройства:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Языки и среды выполнения:** Ruby через `rbenv` (версия 2.7 и две последние версии 3.x, новейшая используется по умолчанию) с Bundler, Node.js 24 с npm, Yarn и pnpm
- **Менеджеры пакетов и версий:** Homebrew, mise
- **Системы контроля версий:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Утилиты:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **Агенты CI:** GitHub Actions runner, Buildkite agent, Bitrise agent и CLI, GitLab job executor
- **Прочее:** Rosetta 2, включён `safaridriver`

Версии инструментов берутся из Homebrew при сборке образа, а сами образы регулярно пересобираются. Чтобы увидеть точную версию на раннере, выведите её в шаге, например `swiftlint version` или `xcodebuild -version`.

### Окружение {#macos-environment}

- **Пользователь и пути.** Задачи выполняются от имени `runner`, с домашней директорией `/Users/runner` и рабочим пространством `/Users/runner/work`, теми же путями, что и у раннеров на GitHub, поэтому действия, жестко задающие эти пути, работают корректно.
- **`sudo`.** Без пароля. Виртуальная машина принадлежит только вашей задаче.
- **Homebrew.** Префикс (`/opt/homebrew`) принадлежит пользователю `runner`, поэтому `brew install <formula>` работает без `sudo`. Установлена переменная `HOMEBREW_NO_AUTO_UPDATE`.
- **Оболочка.** Шаги выполняются в login-оболочке, поэтому Homebrew, `rbenv` и Node.js доступны в `PATH`. Переменная `LANG` имеет значение `en_US.UTF-8`.
- **`ImageOS`** имеет значение `macos26`, как и на раннерах GitHub, для действий настройки, которые выбирают предварительно собранные бинарные файлы по этому значению.
- **Сертификаты.** Промежуточные сертификаты Apple WWDR (G3) и Developer ID (G2) находятся в системном хранилище доверенных сертификатов для подписи и нотариального заверения.
- **Разрешения конфиденциальности.** Два разрешения конфиденциальности macOS предоставляются заранее, как на образах GitHub: скриптовый доступ к Finder через Apple Events, который требуется `create-dmg` и `osascript`, и доступ симулятора iOS к микрофону, который нужен приложениям, записывающим аудио в UI-тестах. Разрешения внутри симулятора, такие как `simctl privacy`, остаются ответственностью вашей задачи.
- **Диск.** Каждая задача начинается как минимум с 100 ГБ свободного места на диске.

### Не включено {#macos-not-included}

- **Tuist CLI.** Установите его в ходе задачи, например с помощью mise, чтобы ваш проект контролировал версию.
- **Другие версии Xcode.** Используйте отдельный профиль для каждой версии Xcode вместо `xcode-select`.
- **Docker.** На раннерах macOS нет демона Docker. Используйте профиль Linux; см. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **Инструментарии, которые GitHub поставляет на macOS** и которые редко требуются для сборок iOS, например Java, Android SDK, .NET, Rust, версии Python или браузеры. Установите их в шаге задачи с помощью Homebrew, mise или действия настройки.

## Linux {#linux}

Раннеры Linux — это виртуальные машины x86_64 (amd64) на базе **Ubuntu 24.04** или **Ubuntu 22.04**, выбор зависит от профиля. См. <.localized_link href="/guides/features/runners/profiles#linux">Профили</.localized_link>, чтобы узнать, как выбрать релиз.

### Предустановленное ПО {#linux-software}

- **Сборочный инструментарий:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Заголовочные файлы для разработки:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 с `pip` и `venv` (версия из релиза Ubuntu)
- **Контейнеры:** Docker CLI с Buildx и Compose; демон работает параллельно с задачей (см. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK находится в `/usr/local/lib/android/sdk` и включает инструменты командной строки, platform-tools, а также все релизы платформ и build-tools начиная с API 34, лицензии приняты
- **Системы контроля версий:** Git, Git LFS, клиент OpenSSH, GitHub CLI (`gh`)
- **Клиенты баз данных:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Архиваторы:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Утилиты:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **Агенты CI:** раннер GitHub Actions, агент Buildkite, агент и CLI Bitrise, исполнитель задач GitLab

### Окружение {#linux-environment}

- **Пользователь и пути.** Задачи выполняются от имени пользователя `runner` (UID 1000) с домашним каталогом `/home/runner`, в группе `docker`, с возможностью выполнения `sudo` без пароля.
- **`ImageOS`** имеет значение `ubuntu24` или `ubuntu22`, что соответствует раннерам GitHub.
- **Android.** Переменные `ANDROID_HOME` и `ANDROID_SDK_ROOT` указывают на SDK. Эмулятор не предустановлен; см. <.localized_link href="/guides/features/runners#android-emulators">Эмуляторы Android</.localized_link>.
- **Локаль.** Переменные `LANG` и `LC_ALL` имеют значение `C.UTF-8`, а `DEBIAN_FRONTEND` — `noninteractive`, поэтому `sudo apt-get install` не выводит запросы.

### Не включено {#linux-not-included}

Образ Linux содержит базовые инструменты сборки, а не все языковые инструментарии, которые предварительно устанавливает GitHub. Установите необходимое для вашей задачи с помощью стандартных действий настройки (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), через mise или с помощью `apt-get`:

- **Среды выполнения языков**, такие как Java, Node.js, Go, Ruby, .NET и Rust.
- **Android NDK.** Установите нужную версию с помощью `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`. Переменная `ANDROID_NDK_HOME` остается неустановленной, чтобы сборка явно завершалась ошибкой, а не ссылалась на отсутствующий NDK.
- **Браузеры** и облачные CLI, кроме `kubectl`, Helm и `gh`.

Чтобы сохранить инструментарий между задачами вместо его установки каждый раз, разместите его на <.localized_link href="/guides/features/runners/cache-volumes">томе кэша</.localized_link>.

## Обновления образов {#image-updates}

Образы пересобираются, когда Apple выпускает новую версию Xcode или бета-версию, когда обновляются агенты CI и когда мы вносим изменения в сами образы. Задача всегда выполняется на полном, протестированном образе: новые образы постепенно развертываются в парке машин и никогда не меняются во время выполнения задачи.

Если инструмент, от которого зависит ваш рабочий процесс, отсутствует, [свяжитесь с нами](mailto:contact@tuist.dev) или спросите в [Slack-сообществе](https://slack.tuist.dev).
