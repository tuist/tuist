---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Предварительный просмотр {#previews}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
<!-- -->
:::

При создании приложения вы можете захотеть поделиться им с другими, чтобы
получить отзывы. Обычно команды делают это, создавая, подписывая и отправляя
свои приложения на такие платформы, как Apple
[TestFlight](https://developer.apple.com/testflight/). Однако этот процесс может
быть трудоемким и медленным, особенно если вам просто нужен быстрый отзыв от
коллеги или друга.

Чтобы упростить этот процесс, Tuist предоставляет возможность создавать и
делиться превью ваших приложений с кем угодно.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
При создании приложения для устройства в настоящее время вы несете
ответственность за правильную подпись приложения. В будущем мы планируем
упростить этот процесс.
<!-- -->
:::

::: code-group
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

Команда сгенерирует ссылку, которой вы можете поделиться с кем угодно, чтобы
запустить приложение — либо на симуляторе, либо на реальном устройстве. Все, что
им нужно сделать, — это выполнить следующую команду:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

При обмене файлом `.ipa` вы можете загрузить приложение напрямую с мобильного
устройства, используя ссылку «Предварительный просмотр». Ссылки на
предварительный просмотр `.ipa` по умолчанию являются частными _private_, что
означает, что получатель должен пройти аутентификацию с помощью своей учетной
записи Tuist, чтобы загрузить приложение. Вы можете изменить это на
общедоступное в настройках проекта, если хотите поделиться приложением с
кем-либо.

`tuist run` также позволяет запустить последнюю предварительную версию на основе
такого указателя, как `latest`, имени ветки или конкретного хеша коммита:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Убедитесь, что `CFBundleVersion` (версия сборки) является уникальной, используя
номер запуска CI, который предоставляют большинство поставщиков CI. Например, в
GitHub Actions вы можете установить `CFBundleVersion` на переменную
<code v-pre>${{ github.run_number }}</code>.

Загрузка предварительного просмотра с тем же бинарным файлом (сборкой) и тем же
`CFBundleVersion` завершится неудачей.
<!-- -->
:::

## Треки {#tracks}

Треки позволяют организовывать предварительные просмотры в группы с именами.
Например, у вас может быть трек `beta` для внутренних тестеров и трек `nightly`
для автоматических сборок. Треки создаются в режиме отложенного создания —
просто укажите название трека при публикации, и он будет создан автоматически,
если его еще нет.

Чтобы поделиться предварительным просмотром конкретной дорожки, используйте
опцию `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Это полезно для:
- **Организация предварительного просмотра**: Группируйте предварительный
  просмотр по назначению (например, `beta`, `nightly`, `internal`)
- **Обновления в приложении**: SDK Tuist использует треки, чтобы определить, о
  каких обновлениях следует уведомлять пользователей.
- **Фильтрация**: легко находите и управляйте предварительным просмотром по
  трекам в панели управления Tuist.

::: warning PREVIEWS' VISIBILITY
<!-- -->
Доступ к предварительному просмотру имеют только лица, имеющие доступ к
организации, к которой принадлежит проект. Мы планируем добавить поддержку
ссылок с ограниченным сроком действия.
<!-- -->
:::

## Приложение Tuist для macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Чтобы упростить запуск Tuist Previews, мы разработали приложение Tuist для
панели меню macOS. Вместо запуска Previews через Tuist CLI, вы можете
[скачать](https://tuist.dev/download) приложение для macOS. Вы также можете
установить приложение, запустив `brew install --cask tuist/tuist/tuist`.

Теперь, когда вы нажмете «Запустить» на странице предварительного просмотра,
приложение macOS автоматически запустит его на выбранном вами устройстве.

::: warning ТРЕБОВАНИЯ
<!-- -->
Вам необходимо иметь локально установленную программу Xcode и работать в macOS
14 или более поздней версии.
<!-- -->
:::

## Приложение Tuist для iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Подобно приложению для macOS, приложения Tuist для iOS упрощают доступ к вашим
предварительным просмотрам и их запуск.

## Комментарии к pull/merge request {#pullmerge-request-comments}

::: warning ТРЕБУЕТСЯ ИНТЕГРАЦИЯ С GIT
<!-- -->
Чтобы получить автоматические комментарии к запросам pull/merge, интегрируйте
ваш
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist-проект</LocalizedLink>
с
<LocalizedLink href="/guides/server/authentication">Git-платформой</LocalizedLink>.
<!-- -->
:::

Тестирование новых функций должно быть частью любого рецензирования кода. Но
необходимость создавать приложение локально добавляет ненужные сложности, что
часто приводит к тому, что разработчики вообще пропускают тестирование функций
на своих устройствах. Но *что, если бы каждый пулл-реквест содержал ссылку на
сборку, которая автоматически запускала бы приложение на устройстве, выбранном
вами в приложении Tuist для macOS?*

После подключения вашего проекта Tuist к платформе Git, такой как
[GitHub](https://github.com), добавьте <LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink> в ваш рабочий процесс CI. Tuist разместит ссылку на
предварительный просмотр непосредственно в ваших запросах на извлечение:
![Комментарий в приложении GitHub со ссылкой на предварительный просмотр
Tuist](/images/guides/features/github-app-with-preview.png)


## Уведомления об обновлениях в приложении {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) позволяет вашему приложению
определять, когда доступна новая предварительная версия, и уведомлять об этом
пользователей. Это полезно для того, чтобы тестировщики всегда использовали
последнюю версию.

SDK проверяет наличие обновлений в превью-треке **** . Когда вы делитесь превью
с явным треком, используя `--track`, SDK будет искать обновления в этом треке.
Если трек не указан, в качестве трека используется ветка git — поэтому превью,
построенное из основной ветки `` , будет уведомлять только о новых превью, также
построенных из основной ветки `` .

### Установка {#sdk-installation}

Добавьте Tuist SDK в качестве зависимости Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Следите за обновлениями {#sdk-monitor-updates}

Используйте `monitorPreviewUpdates` для периодической проверки новых версий
предварительного просмотра:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### Однократная проверка обновлений {#sdk-single-check}

Для ручной проверки обновлений:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Остановка мониторинга обновлений {#sdk-stop-monitoring}

`monitorPreviewUpdates` возвращает задачу `Task`, которую можно отменить:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
Проверка обновлений автоматически отключается на симуляторах и в сборках App
Store.
<!-- -->
:::

## Значок README {#readme-badge}

Чтобы сделать Tuist Previews более заметными в вашем репозитории, вы можете
добавить значок в файл README `` , который указывает на последнюю версию Tuist
Preview:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Чтобы добавить значок в README `` , используйте следующий маркдаун и замените
дескрипторы учетной записи и проекта на свои:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если ваш проект содержит несколько приложений с разными идентификаторами
пакетов, вы можете указать, к какому приложению следует добавить ссылку, добавив
параметр запроса `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Автоматизация {#automations}

Вы можете использовать флаг `--json`, чтобы получить вывод JSON из команды
`tuist share`:
```
tuist share --json
```

Вывод JSON полезен для создания пользовательских автоматизаций, таких как
публикация сообщения в Slack с помощью вашего поставщика CI. JSON содержит ключ
`url` с полной ссылкой на предварительный просмотр и ключ `qrCodeURL` с
URL-адресом изображения QR-кода, чтобы упростить загрузку предварительных
просмотров с реального устройства. Пример вывода JSON приведен ниже:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
