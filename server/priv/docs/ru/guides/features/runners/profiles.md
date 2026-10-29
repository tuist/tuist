---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# Профили {#profiles}

**Профиль** — это именованная конфигурация машины, привязанная к аккаунту. Вы ссылаетесь на него из поля `runs-on` в воркфлоу, и Tuist направляет задачу на подходящий раннер. Профили позволяют хранить настройки инфраструктуры (платформа, размер, версия Xcode) в одном месте, а не разбрасывать их по всем файлам воркфлоу, и дают стабильную метку для CI.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

Метка представляет собой имя профиля с префиксом `tuist-`. Профиль с именем `macos` соответствует `runs-on: tuist-macos`; профиль с именем `linux-large` соответствует `runs-on: tuist-linux-large`. Сравнение регистронезависимое.

## Профили по умолчанию {#default-profiles}

Каждый аккаунт с включенными раннерами изначально имеет два профиля, чтобы вы могли использовать пул машин без дополнительной настройки:

{{runner_default_profiles_table}}

Оба указывают на <.localized_link href="/guides/features/runners/profiles#machine-shapes">конфигурацию</.localized_link> по умолчанию для своей платформы. Они **защищены**, поэтому их нельзя удалить, а метки, от которых зависят ваши воркфлоу, всегда будут разрешаться. Вы можете изменить их конфигурацию или версию Xcode, а также создать дополнительные профили для других размеров или версий Xcode.

## Конфигурации машин {#machine-shapes}

Раннеры доступны на macOS (Apple Silicon, виртуализированные в парке Mac) и Linux. Каждый профиль закрепляет одну конфигурацию машины — пару `(vCPUs, memory)` — из каталога ниже.

### Linux {#linux}

{{runner_linux_shapes_table}}

Каждый Linux-профиль поддерживает <.localized_link href="/guides/features/runners#android-emulators">аппаратно ускоренные эмуляторы Android</.localized_link> через `/dev/kvm`. Отдельный профиль KVM не требуется.

### macOS {#macos}

{{runner_macos_shapes_table}}

Более мощные конфигурации macOS работают на меньшем количестве машин в пуле, поэтому задача, запрашивающая такую конфигурацию, может ждать запуска дольше, чем та же задача на меньшей конфигурации. Выбирайте более мощную конфигурацию, когда задача ограничена производительностью CPU, а для всего остального оставляйте конфигурацию по умолчанию. Если вы не уверены, запустите задачу на обеих конфигурациях и сравните время выполнения в дашборде.

Профили macOS также закрепляют **версию Xcode**. Версия выбирает образ раннера с предустановленным Xcode, поэтому задачи запускаются с уже настроенным тулчейном. Поддерживаемые версии на сегодня:

{{runner_macos_xcode_versions}}

> [!NOTE]
> Каталог обновляется по мере добавления нового оборудования и выпусков Xcode. Форма **Новый профиль** в дашборде и команда `tuist runner profile catalog` всегда показывают конфигурации и версии Xcode, доступные вашему аккаунту в данный момент, поэтому считайте их источником истины.

Имя раннера macOS показывает версию macOS, версию Xcode профиля и его конфигурацию, например `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`. Это имя отображается в шаге **Set up job** задачи на GitHub и в деталях задачи в дашборде Tuist.

## Создание профиля {#creating-a-profile}

1. Откройте раздел **Runners → Profiles** в дашборде вашего аккаунта.
2. Выберите **New profile**.
3. Задайте имя, выберите платформу и конфигурацию. Для macOS также выберите версию Xcode.
4. Сохраните, затем ссылаетесь на него из воркфлоу с помощью `runs-on: tuist-<name>`.

Вы также можете управлять профилями из командной строки. Создание, изменение и удаление профилей требует прав администратора аккаунта, как в дашборде, или токена аккаунта с областью доступа `account:runners:write`:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Агенты могут делать то же самое через <.localized_link href="/guides/features/agentic-coding/mcp">MCP-сервер</.localized_link>.

Например, профиль с именем `linux-large` на конфигурации 8 vCPU / 32 ГБ:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

Или профиль macOS с именем `xcode-26-4`, закрепленный за Xcode `26.4.1`, чтобы задача могла выполняться на более старом тулчейне, пока ваш профиль `macos` по умолчанию отслеживает последнюю версию:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
