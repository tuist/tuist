---
{
  "title": "Previews",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Мгновенно делитесь сборками приложений для iOS и Android с помощью Tuist Previews. Отправьте ссылку коллегам и заинтересованным сторонам — настройка TestFlight или Play Console не требуется."
}
---
# Предпросмотры {#previews}

Tuist Previews позволяют создавать и делиться предпросмотрами приложений, чтобы коллеги могли тестировать сборки без локальной пересборки.

При сборке приложения вы можете захотеть поделиться им с другими для получения обратной связи. Традиционно команды делают это, собирая, подписывая и отправляя свои приложения на такие платформы, как Apple [TestFlight](https://developer.apple.com/testflight/). Однако этот процесс может быть громоздким и медленным, особенно когда вам нужна быстрая обратная связь от коллеги или друга.

Чтобы упростить этот процесс, Tuist предоставляет возможность создавать предпросмотры ваших приложений и делиться ими с кем угодно.

> [!WARNING]
> **Сборки для устройств должны быть подписаны**
>
> При сборке для устройства сейчас ваша задача — убедиться, что приложение правильно подписано. В будущем мы планируем упростить этот процесс.

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

Команда сгенерирует ссылку, которой вы можете поделиться с любым человеком для запуска приложения — либо в симуляторе, либо на реальном устройстве. Всё, что им нужно сделать, — выполнить команду ниже:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

При обмене файлом `.ipa` вы можете скачать приложение прямо с мобильного устройства по ссылке на предпросмотр. Ссылки на предпросмотры `.ipa` по умолчанию _приватные_, то есть получателю нужно авторизоваться через свой аккаунт Tuist, чтобы скачать приложение. Вы можете изменить это на публичный доступ в настройках проекта, если хотите делиться приложением со всеми.

`tuist run` также позволяет запускать последний предпросмотр на основе спецификатора, такого как `latest`, имя ветки или конкретный хеш коммита:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Уникальные номера сборок в CI**
>
> Убедитесь, что `CFBundleVersion` (версия сборки) уникальна, используя номер запуска CI, который предоставляют большинство провайдеров CI. Например, в GitHub Actions вы можете установить для `CFBundleVersion` переменную <code v-pre>${{ github.run_number }}</code>. 
>
> Загрузка предпросмотра с тем же бинарным файлом (сборкой) и тем же `CFBundleVersion` завершится ошибкой.

## Треки {#tracks}

Треки позволяют организовывать предпросмотры в именованные группы. Например, у вас может быть трек `beta` для внутренних тестировщиков и трек `nightly` для автоматических сборок. Треки создаются лениво: просто укажите имя трека при публикации, и он будет создан автоматически, если ещё не существует.

Чтобы поделиться предпросмотром в конкретном треке, используйте опцию `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Это полезно для:
- **Организации предпросмотров**: группируйте предпросмотры по назначению (например, `beta`, `nightly`, `internal`)
- **Обновлений внутри приложения**: Tuist SDK использует треки, чтобы определять, о каких обновлениях уведомлять пользователей
- **Фильтрации**: легко находите и управляйте предпросмотрами по трекам в панели управления Tuist

> [!WARNING]
> **Видимость предпросмотров**
>
> Доступ к предпросмотрам имеют только люди с доступом к организации, которой принадлежит проект. Мы планируем добавить поддержку ссылок с истечением срока действия.

## Примечания к выпуску {#release-notes}

Используйте треки для групп окружений и примечания к выпуску для описания конкретной сборки:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Примечания к выпуску — это необязательный простой текст до 10 000 символов. Первая непустая строка отображается как однострочный фрагмент в веб-списках и списках предпросмотров iOS, поэтому номера сборок и другая идентифицирующая информация видны сразу. Длинные строки обрезаются; полные примечания появляются на страницах деталей. Поиск в обоих списках совпадает с отображаемыми именами и полными примечаниями к выпуску, включая строки, не показанные во фрагменте. Поддерживаются многострочные примечания, например `--release-notes "$(< release-notes.txt)"`. Они не меняют отображаемое имя приложения или его трек.

### Совместимость {#preview-metadata-compatibility}

Примечания к выпуску — это добавочные метаданные, а не часть идентичности предпросмотра. Загрузки от старых и новых клиентов всё равно группируются в один предпросмотр на разных платформах. Первые непустые примечания сохраняются: последующая загрузка может заполнить ранее отсутствующие примечания, но не может перезаписать существующие. Пропуск `release_notes`, отправка `null` или отправка пустой строки либо строки, состоящей только из пробелов, никогда не очищает примечания. Существующие предпросмотры не заполняются ретроспективно и остаются действительными без примечаний.

Необязательный параметр запроса `track` API списка совпадает с полным именем трека без учёта регистра, что согласуется с существующим хранением треков. Опустите его или отправьте пустое значение (`?track=`), чтобы вывести список всех треков. Имена треков остаются произвольными строками, а не фиксированным списком значений. Выбор **All Tracks** в приложении iOS исключает фильтр. Виджеты треков в приложении iOS загружают полную сводку проекта из `GET /api/projects/:account_handle/:project_handle/previews/tracks` с теми же правами на чтение предпросмотров, что и при перечислении сборок. Эта конечная точка возвращает `{total_count, tracks: [{name, count}]}` с отсортированными, сгруппированными без учёта регистра именами треков. Счётчики охватывают весь проект независимо от пагинации, поиска и выбранного трека; общее количество включает предпросмотры без трека. Учитываются только перечисляемые предпросмотры с идентификатором пакета. API списка также принимает необязательный параметр `search` для буквального подстрокового поиска без учёта регистра в отображаемом имени или полных примечаниях к выпуску, применяемого вместе с треком до пагинации. Существующая фильтрация по `display_name` остаётся точной.

Старые клиенты могут продолжать загружать и перечислять предпросмотры без отправки этих полей. Новые клиенты принимают более старые ответы, в которых отсутствуют трек или примечания, и игнорируют неизвестные свойства ответа, добавленные будущими серверами. Интеграции API также должны игнорировать неизвестные свойства ответа, чтобы добавочные метаданные оставались совместимыми.

Для использования этих функций в развёртываниях на собственных серверах требуется версия сервера, поддерживающая примечания к выпуску и фильтрацию по трекам, а также обновлённые CLI и приложение. Более старые серверы могут игнорировать примечания или неизвестные параметры запроса. Если обнаружение треков недоступно, приложение iOS сохраняет возможность просмотра без фильтров и сообщает, что выбор трека требует обновлённого сервера. Если сервер возвращает предпросмотры из другого трека несмотря на активный фильтр, приложение iOS сообщает, что фильтрация не поддерживается, вместо того чтобы показывать вводящие в заблуждение результаты. Приложение macOS сначала запрашивает последний совместимый предпросмотр для каждого приложения; на более старых серверах, которые выбирают отдельные приложения до применения фильтров платформы, оно переходит к постраничной истории без установки ограничения, которое могло бы скрыть доступную сборку.

## Приложение Tuist для macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Чтобы ещё проще запускать Tuist Previews, мы разработали приложение Tuist для меню macOS. Вместо запуска предпросмотров через CLI Tuist вы можете [скачать](https://tuist.dev/download) приложение для macOS. Вы также можете установить приложение, выполнив `brew install --cask tuist/tuist/tuist`.

Когда вы нажимаете «Run» на странице предпросмотра, приложение macOS автоматически запускает его на выбранном устройстве.

## Приложение Tuist для iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Скачать в App Store" style="height: 40px;">
    </a>
</div>

Как и приложение для macOS, приложение Tuist для iOS упрощает доступ к предпросмотрам и их запуск. Каждый предпросмотр показывает свой трек. Используйте поле поиска, чтобы найти предпросмотры по названию приложения, затем выберите тег под **Треки**, чтобы отфильтровать по окружению. Выбранный тег подсвечивается фиолетовым; выберите **Все**, чтобы снять фильтр по треку. Каждый тег показывает общее количество предпросмотров проекта, а «Все» включает сборки без трека. Поиск и фильтрация по трекам применяются ко всем страницам, а не только к уже загруженным предпросмотрам. Тег трека каждой сборки находится рядом с хешем коммита.

## Комментарии к пул-реквестам/мерж-реквестам {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-платформой**
>
> Чтобы получать автоматические комментарии к пул-реквестам/мерж-реквестам, интегрируйте ваш <.localized_link href="/guides/server/accounts-and-projects">удалённый проект</.localized_link> с <.localized_link href="/guides/server/authentication">Git-платформой</.localized_link>.

Тестирование нового функционала должно быть частью любого код-ревью. Но необходимость собирать приложение локально создаёт лишние трудности, из-за чего разработчики часто вообще пропускают тестирование функционала на устройстве. А *что если бы каждый пул-реквест содержал ссылку на сборку, которая автоматически запускала бы приложение на устройстве, выбранном в приложении Tuist для macOS?*

После подключения вашего проекта Tuist к Git-платформе, такой как [GitHub](https://github.com), добавьте <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> в ваш CI-воркфлоу. Tuist опубликует ссылку на предпросмотр прямо в ваших пул-реквестах: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/github-app-with-preview.png)

## Уведомления об обновлениях внутри приложения {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) позволяет вашему приложению определять, когда доступна новая версия предпросмотра, и уведомлять пользователей. Это полезно для того, чтобы тестировщики всегда использовали последнюю сборку.

SDK проверяет обновления в рамках одного **трека предпросмотра**. Когда вы делитесь предпросмотром с явным указанием трека через `--track`, SDK будет искать обновления в этом треке. Если трек не указан, в качестве трека используется ветка git — поэтому предпросмотр, собранный из ветки `main`, будет уведомлять только о новых предпросмотрах, также собранных из `main`.

### Установка {#sdk-installation}

Добавьте Tuist SDK как зависимость Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Отслеживание обновлений {#sdk-monitor-updates}

Используйте `monitorPreviewUpdates`, чтобы периодически проверять наличие новых версий предпросмотра:

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

### Единичная проверка обновления {#sdk-single-check}

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

### Остановка отслеживания обновлений {#sdk-stop-monitoring}

`monitorPreviewUpdates` возвращает `Task`, который можно отменить:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> Проверка обновлений автоматически отключена на симуляторах и в сборках для App Store.

## Бейдж для README {#readme-badge}

Чтобы сделать Tuist Previews более заметными в вашем репозитории, вы можете добавить бейдж в файл `README`, который указывает на последний Tuist Preview:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Чтобы добавить бейдж в ваш `README`, используйте следующий markdown и замените идентификаторы аккаунта и проекта на свои:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если ваш проект содержит несколько приложений с разными bundle identifiers, вы можете указать, предпросмотр какого приложения использовать, добавив параметр запроса `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Автоматизации {#automations}

Вы можете использовать флаг `--json`, чтобы получить JSON-вывод команды `tuist share`:
```
tuist share --json
```

JSON-вывод полезен для создания пользовательских автоматизаций, например, отправки сообщения в Slack через ваш CI-провайдер. JSON содержит ключ `url` с полной ссылкой на предпросмотр и ключ `qrCodeURL` с URL изображения QR-кода, что упрощает скачивание предпросмотров на реальное устройство. Пример JSON-вывода приведён ниже:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
