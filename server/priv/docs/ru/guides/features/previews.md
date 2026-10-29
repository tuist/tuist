---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share iOS and Android app builds instantly with Tuist Previews. Give teammates and stakeholders a link, no TestFlight or Play Console setup required."
}
---
# Previews {#previews}

Tuist Previews позволяют генерировать и делиться превью приложений, чтобы коллеги могли тестировать сборки без локальной пересборки.

При сборке приложения вы можете захотеть поделиться им с другими для получения обратной связи. Традиционно команды делают это, собирая, подписывая и отправляя свои приложения на такие платформы, как Apple [TestFlight](https://developer.apple.com/testflight/). Однако этот процесс может быть громоздким и медленным, особенно если вам нужна быстрая обратная связь от коллеги или друга.

Чтобы упростить этот процесс, Tuist предоставляет возможность генерировать превью ваших приложений и делиться ими с кем угодно.

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

Команда сгенерирует ссылку, которой вы сможете поделиться с любым человеком для запуска приложения — либо на симуляторе, либо на реальном устройстве. Всё, что им нужно сделать, — выполнить команду ниже:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

При обмене файлом `.ipa` вы можете скачать приложение прямо с мобильного устройства, используя ссылку Preview. Ссылки на превью `.ipa` по умолчанию _приватные_, то есть получателю необходимо аутентифицироваться в своей учётной записи Tuist, чтобы скачать приложение. Вы можете изменить это на публичный доступ в настройках проекта, если хотите делиться приложением с кем угодно.

`tuist run` также позволяет запустить последнее превью на основе спецификатора, такого как `latest`, имя ветки или конкретный хеш коммита:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Уникальные номера сборок в CI**
>
> Убедитесь, что `CFBundleVersion` (версия сборки) уникальна, используя номер запуска CI, который предоставляют большинство провайдеров CI. Например, в GitHub Actions вы можете установить `CFBundleVersion` в переменную <code v-pre>${{ github.run_number }}</code>. 
>
> Загрузка превью с тем же бинарным файлом (сборкой) и тем же `CFBundleVersion` завершится ошибкой.

## Tracks {#tracks}

Tracks позволяют организовывать превью в именованные группы. Например, у вас может быть трек `beta` для внутренних тестировщиков и трек `nightly` для автоматизированных сборок. Треки создаются лениво — просто укажите имя трека при обмене, и он будет создан автоматически, если ещё не существует.

Чтобы поделиться превью в конкретном треке, используйте опцию `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Это полезно для:
- **Организации превью**: группируйте превью по назначению (например, `beta`, `nightly`, `internal`)
- **Обновлений внутри приложения**: Tuist SDK использует треки, чтобы определять, о каких обновлениях уведомлять пользователей
- **Фильтрации**: легко находите и управляйте превью по трекам в панели управления Tuist

> [!WARNING]
> **Видимость превью**
>
> Доступ к превью имеют только люди с доступом к организации, которой принадлежит проект. Мы планируем добавить поддержку ссылок с истечением срока действия.

## Release notes {#release-notes}

Используйте треки для группировки по окружениям и release notes для описания конкретной сборки:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes — это необязательный простой текст длиной до 10 000 символов. Первая непустая строка отображается как однострочный фрагмент в веб-списках и списках превью iOS, поэтому номера сборок и другая идентифицирующая информация видны сразу. Длинные строки обрезаются; полные заметки отображаются на страницах деталей. Поиск в обоих списках совпадает с отображаемыми именами и полными release notes, включая строки, не показанные во фрагменте. Поддерживаются многострочные заметки, например `--release-notes "$(< release-notes.txt)"`. Они не изменяют отображаемое имя приложения или его трек.

### Compatibility {#preview-metadata-compatibility}

Release notes — это добавочные метаданные, не являющиеся частью идентичности превью. Загрузки от старых и новых клиентов всё равно группируются в одно и то же превью на разных платформах. Первые непустые заметки сохраняются: последующая загрузка может заполнить ранее отсутствовавшие заметки, но не может перезаписать существующие. Пропуск `release_notes`, отправка `null` или отправка пустой строки либо строки, состоящей только из пробельных символов, никогда не очищает заметки. Существующие превью не заполняются ретроспективно и остаются действительными без заметок.

Необязательный параметр запроса `track` list API сопоставляет полное имя трека без учёта регистра, что согласуется с существующим хранением треков. Опустите его или отправьте пустое значение (`?track=`), чтобы перечислить все треки. Имена треков остаются открытыми строками, а не фиксированным списком значений. Выбор **All Tracks** в приложении iOS опускает фильтр. Pill-кнопки треков в приложении iOS загружают полную сводку проекта из `GET /api/projects/:account_handle/:project_handle/previews/tracks` с теми же правами доступа на чтение превью, что и при перечислении сборок. Этот эндпоинт возвращает `{total_count, tracks: [{name, count}]}` с отсортированными, сгруппированными без учёта регистра названными треками. Счётчики охватывают весь проект независимо от пагинации, поиска и выбранного трека; общее количество включает превью без трека. Учитываются только перечисляемые превью с идентификатором пакета. List API также принимает необязательный `search` для буквального, нечувствительного к регистру подстроки отображаемого имени или полных release notes, комбинируемой с треком перед пагинацией. Существующая фильтрация по `display_name` остаётся точной.

Старые клиенты могут продолжать загружать и перечислять превью, не отправляя ни одно из этих полей. Новые клиенты принимают более старые ответы, в которых отсутствуют трек или заметки, и игнорируют неизвестные свойства ответа, добавленные будущими серверами. Интеграции API также должны игнорировать неизвестные свойства ответа, чтобы добавочные метаданные оставались совместимыми.

Для использования этих функций саморазвёрнутым инстансам требуется версия сервера, поддерживающая release notes и фильтрацию по трекам, вместе с обновлёнными CLI и приложением. Более старые серверы могут игнорировать заметки или неизвестные параметры запроса. Если обнаружение треков недоступно, приложение iOS сохраняет возможность просмотра без фильтров и объясняет, что выбор трека требует обновлённого сервера. Если сервер возвращает превью из другого трека несмотря на активный фильтр, приложение iOS сообщает, что фильтрация не поддерживается, вместо того чтобы показывать вводящие в заблуждение результаты. Приложение macOS сначала запрашивает последнее совместимое превью для каждого приложения; на более старых серверах, которые выбирают отдельные приложения перед применением фильтров платформ, оно переходит к постраничной истории, не накладывая ограничение, которое могло бы скрыть доступную сборку.

## Приложение Tuist для macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Чтобы ещё проще запускать Tuist Previews, мы разработали приложение Tuist для строки меню macOS. Вместо запуска Previews через CLI Tuist вы можете [скачать](https://tuist.dev/download) приложение для macOS. Вы также можете установить приложение, выполнив `brew install --cask tuist/tuist/tuist`.

Когда вы нажимаете «Run» на странице Preview, приложение для macOS автоматически запускает его на вашем текущем выбранном устройстве.

## Приложение Tuist для iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Скачать в App Store" style="height: 40px;">
    </a>
</div>

Как и приложение для macOS, приложение Tuist для iOS упрощает доступ к вашим превью и их запуск. Каждое превью отображает свой трек. Используйте поле нативного поиска, чтобы найти превью по имени приложения, затем выберите метку под **Tracks**, чтобы отфильтровать по окружению. Выбранная метка становится фиолетовой; выберите **All**, чтобы снять фильтр по треку. Каждая метка показывает количество превью во всём проекте, а All включает сборки без трека. Поиск и фильтрация по трекам применяются ко всем страницам, а не только к уже загруженным превью. Метка трека каждой сборки находится рядом с её хешем коммита.

## Комментарии к pull/merge request {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-платформой**
>
> Чтобы получать автоматические комментарии к pull/merge request, интегрируйте ваш <.localized_link href="/guides/server/accounts-and-projects">удалённый проект</.localized_link> с <.localized_link href="/guides/server/authentication">Git-платформой</.localized_link>.

Тестирование новой функциональности должно быть частью любого код-ревью. Но необходимость собирать приложение локально создаёт ненужные препятствия, из-за чего разработчики часто вообще пропускают тестирование функциональности на своём устройстве. А *что если бы каждый pull request содержал ссылку на сборку, которая автоматически запускала бы приложение на устройстве, выбранном вами в приложении Tuist для macOS?*

Как только ваш проект Tuist подключён к вашей Git-платформе, такой как [GitHub](https://github.com), добавьте <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> в ваш CI-воркфлоу. После этого Tuist опубликует ссылку на Preview прямо в ваших pull request: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/github-app-with-preview.png)

## Уведомления об обновлениях внутри приложения {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) позволяет вашему приложению определять, когда доступна более новая версия превью, и уведомлять пользователей. Это полезно для того, чтобы тестировщики всегда использовали последнюю сборку.

SDK проверяет обновления в пределах одного и того же **трека превью**. Когда вы делитесь превью с явным указанием трека через `--track`, SDK будет искать обновления именно в этом треке. Если трек не указан, в качестве трека используется git-ветка — поэтому превью, собранное из ветки `main`, будет уведомлять только о новых превью, также собранных из `main`.

### Установка {#sdk-installation}

Добавьте Tuist SDK как зависимость Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Мониторинг обновлений {#sdk-monitor-updates}

Используйте `monitorPreviewUpdates`, чтобы периодически проверять наличие новых версий превью:

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

### Остановка мониторинга обновлений {#sdk-stop-monitoring}

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

Чтобы сделать Tuist Previews более заметными в вашем репозитории, вы можете добавить бейдж в файл `README`, который указывает на последнее Tuist Preview:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Чтобы добавить бейдж в ваш `README`, используйте следующий markdown и замените handle аккаунта и проекта на свои:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если ваш проект содержит несколько приложений с разными bundle identifiers, вы можете указать, превью какого приложения ссылать, добавив параметр запроса `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Автоматизации {#automations}

Вы можете использовать флаг `--json`, чтобы получить JSON-вывод из команды `tuist share`:
```
tuist share --json
```

JSON-вывод полезен для создания пользовательских автоматизаций, например, отправки сообщения в Slack через вашего CI-провайдера. JSON содержит ключ `url` с полной ссылкой на превью и ключ `qrCodeURL` с URL изображения QR-кода, что упрощает скачивание превью с реального устройства. Пример JSON-вывода приведён ниже:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
