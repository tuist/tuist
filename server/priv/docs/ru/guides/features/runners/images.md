---
{
  "title": "Образы",
  "titleTemplate": ":title · Раннеры · Возможности · Руководства · Tuist",
  "description": "Что предустановлено в раннерах Tuist: образы macOS с Xcode, симуляторами и инструментарием Metal, а также образы Ubuntu с Docker и Android SDK."
}
---
# Образы {#images}

Каждая задача Tuist Runners запускается на чистой виртуальной машине, загруженной из образа раннера. Ваш <.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> выбирает образ: платформу, версию Xcode на macOS и релиз Ubuntu на Linux. ВМ удаляется после завершения задачи, поэтому всё, что установила задача, исчезает для следующей.

Образы следуют за GitHub-hosted runners там, где это важно для рабочих процессов: те же пути пользователя, домашней директории и рабочей области, `ImageOS`, `sudo` без пароля и инструменты, которые ожидают большинство рабочих процессов для iOS, macOS и Linux. Они намеренно меньше образов GitHub, поэтому различия перечислены ниже для каждой платформы.

## Выбор образа {#choosing-an-image}

- **Xcode, Apple SDK или симуляторы:** профиль macOS, привязанный к версии Xcode, с которой собирается ваш проект.
- **Docker, сборки Android и эмуляторы или другие инструменты Linux:** профиль Linux на Ubuntu 24.04.
- **Зависимость, которая ещё не поддерживает Ubuntu 24.04:** профиль Linux на Ubuntu 22.04.

На macOS вы выбираете Xcode, а не образ: каждая версия Xcode — это отдельный образ, и профиль, привязанный к `26.4.1`, всегда выполняется на образе, собранном с Xcode 26.4.1. Чтобы использовать две версии Xcode, создайте по профилю для каждой.

## macOS {#macos}

Раннеры macOS — это виртуальные машины на Apple Silicon (arm64), работающие под управлением **macOS 26 Tahoe** или **macOS 27 Golden Gate**, в зависимости от того, какая ОС указана в параметре **Operating system** профиля. Профили, созданные до появления этого выбора, работают на Tahoe. Каждая версия Xcode собирается отдельно для каждого релиза macOS, поэтому доступные версии Xcode зависят от выбранной операционной системы. Имя раннера включает точную версию macOS, например `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, и отображается в шаге задачи **Set up job**.

### Xcode {#xcode}

Каждый образ содержит **ровно одну версию Xcode**, которая выбирается с помощью `xcode-select`, поэтому `xcodebuild` и `xcrun` используют её без дополнительного шага настройки. Это главное отличие от образов GitHub-hosted, которые поставляют несколько версий Xcode для переключения во время выполнения задачи. Доступные версии:

{{runner_macos_xcode_versions}}

- **Путь.** Xcode находится в `/Applications/Xcode_<version>.app`. Для версии с патчем `/Applications/Xcode_<major>.<minor>.app` указывает на тот же бандл, поэтому `Xcode_26.4.app` разрешается в `Xcode_26.4.1.app`. Рабочие процессы, которые жестко кодируют путь в стиле GitHub или вызывают `xcode-select -s` с ним, продолжают работать.
- **Симуляторы.** Среды выполнения симуляторов iOS, tvOS, watchOS и visionOS, поставляемые с этой версией Xcode, загружены в образ, поэтому первый запуск `xcodebuild test` не требует их загрузки.
- **Metal toolchain.** Начиная с Xcode 26, компилятор Metal не входит в состав Xcode и должен загружаться отдельно. Каждый образ включает Metal toolchain, соответствующий его версии Xcode, установленный для пользователя, от имени которого выполняются задачи, поэтому `xcrun metal` и проекты с исходниками `.metal` собираются без запуска `xcodebuild -downloadComponent MetalToolchain`.
- **Бета-версии.** Бета-профили (например, `27.3-beta`) отслеживают последнюю бета-версию этого релиза. Когда Apple выпускает новую бета-версию, образ пересобирается, и профиль автоматически переключается на неё без изменений с вашей стороны.

### Предустановленное ПО {#macos-software}

- **Инструменты Apple:** Xcode (одна версия на образ), среды выполнения симуляторов, Metal toolchain, `xcodes`, `xcbeautify`
- **Инструменты Swift и iOS:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Устройства:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Языки и среды выполнения:** Ruby через `rbenv` (2.7 и две последние версии 3.x, новейшая по умолчанию) с Bundler, Node.js 24 с npm, Yarn и pnpm, Go, Java 21 (Temurin, установлено как `JAVA_HOME`)
- **Менеджеры пакетов и версий:** Homebrew, mise
- **Контроль версий:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Утилиты:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **Агенты CI:** GitHub Actions runner, Buildkite agent, Bitrise agent и CLI, GitLab job executor
- **Другое:** Rosetta 2, включён `safaridriver`

Версии инструментов берутся из Homebrew при сборке образа, а образы регулярно пересобираются. Чтобы увидеть точную версию на раннере, выведите её в шаге, например `swiftlint version` или `xcodebuild -version`.

### Окружение {#macos-environment}

- **Пользователь и пути.** Задачи выполняются от имени `runner`, с домашней директорией `/Users/runner` и рабочей областью `/Users/runner/work`, теми же путями, что и у GitHub-hosted runners, поэтому действия, жестко кодирующие их, работают.
- **`sudo`.** Без пароля. ВМ принадлежит только вашей задаче.
- **Homebrew.** Префикс (`/opt/homebrew`) принадлежит `runner`, поэтому `brew install <formula>` работает без `sudo`. Установлено `HOMEBREW_NO_AUTO_UPDATE`.
- **Оболочка.** Шаги выполняются в login shell, поэтому Homebrew, `rbenv` и Node.js находятся в `PATH`. `LANG` равен `en_US.UTF-8`.
- **`ImageOS`** равен `macos26`, как на GitHub-hosted runners, для действий настройки, которые выбирают предварительно собранные бинарные файлы по этому значению.
- **Сертификаты.** Промежуточные сертификаты Apple WWDR (G3) и Developer ID (G2) находятся в системном хранилище доверия для подписи и нотариализации.
- **Разрешения конфиденциальности.** Два разрешения конфиденциальности macOS предоставляются заранее, как на образах GitHub-hosted: скриптинг Finder через Apple Events, который нужен `create-dmg` и `osascript`, и доступ iOS Simulator к микрофону, который нужен приложениям, записывающим аудио в UI-тестах. Разрешения внутри симулятора, такие как `simctl privacy`, остаются ответственностью вашей задачи.
- **Диск.** Каждая задача начинается как минимум с 100 ГБ свободного места на диске.

### Не включено {#macos-not-included}

- **Tuist CLI.** Установите его в задаче, например с помощью mise, чтобы ваш проект контролировал версию.
- **Другие версии Xcode.** Используйте отдельный профиль для каждой версии Xcode вместо `xcode-select`.
- **Docker.** На раннерах macOS нет демона Docker. Используйте профиль Linux; см. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **Инструментальные цепочки, которые GitHub предоставляет на macOS** и которые редко нужны для сборок iOS, например другие версии Java, Android SDK, .NET, Rust, версии Python или браузеры. Установите их в шаге с помощью Homebrew, mise или действия настройки.

## Linux {#linux}

Раннеры Linux — это виртуальные машины x86_64 (amd64) на базе **Ubuntu 24.04** или **Ubuntu 22.04**, выбор зависит от профиля. См. <.localized_link href="/guides/features/runners/profiles#linux">Профили</.localized_link>, чтобы узнать, как выбрать релиз.

### Предустановленное ПО {#linux-software}

- **Сборочная инструментальная цепочка:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Заголовочные файлы для разработки:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 с `pip` и `venv` (версия из релиза Ubuntu)
- **Контейнеры:** Docker CLI с Buildx и Compose; демон работает параллельно с задачей (см. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK по пути `/usr/local/lib/android/sdk` с инструментами командной строки, platform-tools и всеми релизами платформ и build-tools начиная с API 34, лицензии приняты
- **Системы контроля версий:** Git, Git LFS, клиент OpenSSH, GitHub CLI (`gh`)
- **Клиенты баз данных:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Архиваторы:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Утилиты:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **Агенты CI:** GitHub Actions runner, Buildkite agent, Bitrise agent и CLI, GitLab job executor

### Окружение {#linux-environment}

- **Пользователь и пути.** Задачи выполняются от имени `runner` (UID 1000) с домашним каталогом `/home/runner`, в группе `docker`, с `sudo` без пароля.
- **`ImageOS`** равен `ubuntu24` или `ubuntu22`, что соответствует раннерам GitHub-hosted.
- **Android.** `ANDROID_HOME` и `ANDROID_SDK_ROOT` указывают на SDK. Эмулятор не предустановлен; см. <.localized_link href="/guides/features/runners#android-emulators">Эмуляторы Android</.localized_link>.
- **Локаль.** `LANG` и `LC_ALL` равны `C.UTF-8`, а `DEBIAN_FRONTEND` установлен в `noninteractive`, поэтому `sudo apt-get install` не запрашивает ввод.

### Не включено {#linux-not-included}

Образ Linux покрывает основы сборки, а не все языковые инструментальные цепочки, которые GitHub предустанавливает. Установите то, что нужно вашей задаче, с помощью обычных действий настройки (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), через mise или с помощью `apt-get`:

- **Языковые среды выполнения**, такие как Java, Node.js, Go, Ruby, .NET и Rust.
- **Android NDK.** Установите нужную версию с помощью `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`. `ANDROID_NDK_HOME` остается неустановленным, чтобы сборка явно завершалась ошибкой, а не указывала на отсутствующий NDK.
- **Браузеры** и облачные CLI, кроме `kubectl`, Helm и `gh`.

Чтобы сохранить инструментальную цепочку между задачами вместо установки каждый раз, поместите её в <.localized_link href="/guides/features/runners/cache-volumes">том кэша</.localized_link>.

## Обновления образов {#image-updates}

Образы пересобираются, когда Apple выпускает новый Xcode или бета-версию, когда обновляются агенты CI и когда мы изменяем сами образы. Задача всегда выполняется на полном, протестированном образе: новые образы постепенно развертываются в парке и никогда не меняются во время выполнения задачи.

Если инструмент, от которого зависит ваш workflow, отсутствует, [свяжитесь с нами](mailto:contact@tuist.dev) или спросите в [Slack сообщества](https://slack.tuist.dev).
