---
{
  "title": "Previews",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Мгновенно делитесь сборками приложений для iOS и Android с помощью Tuist Previews. Просто отправьте ссылку коллегам и заинтересованным сторонам — настройка TestFlight или Play Console не требуется."
}
---
# Превью {#previews}

Tuist Previews позволяют создавать и делиться превью приложений, чтобы коллеги могли тестировать сборки без локальной пересборки.

При сборке приложения вы можете захотеть поделиться им с другими для получения обратной связи. Традиционно команды делают это, собирая, подписывая и публикуя приложения на таких платформах, как Apple [TestFlight](https://developer.apple.com/testflight/). Однако этот процесс может быть громоздким и медленным, особенно если вам нужна быстрая обратная связь от коллеги или друга.

Чтобы упростить этот процесс, Tuist предоставляет возможность создавать превью ваших приложений и делиться ими с кем угодно.

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

Команда сгенерирует ссылку, которой вы можете поделиться с кем угодно для запуска приложения — либо на симуляторе, либо на реальном устройстве. Им нужно будет лишь выполнить команду ниже:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

При обмене файлом `.ipa` вы можете скачать приложение прямо с мобильного устройства по ссылке на превью. Ссылки на превью `.ipa` по умолчанию _приватные_, то есть получателю необходимо авторизоваться в своей учетной записи Tuist, чтобы скачать приложение. Вы можете изменить настройку на публичную в параметрах проекта, если хотите делиться приложением со всеми.

`tuist run` также позволяет запускать последнее превью по спецификатору, например `latest`, имени ветки или конкретному хешу коммита:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Уникальные номера сборок в CI**
>
> Убедитесь, что `CFBundleVersion` (версия сборки) уникальна, используя номер запуска CI, который предоставляют большинство провайдеров CI. Например, в GitHub Actions можно задать для `CFBundleVersion` переменную <code v-pre>${{ github.run_number }}</code>. 
>
> Загрузка превью с тем же бинарным файлом (сборкой) и тем же `CFBundleVersion` завершится ошибкой.

## Треки {#tracks}

Треки позволяют группировать превью по именам. Например, у вас может быть трек `beta` для внутренних тестировщиков и трек `nightly` для автоматических сборок. Треки создаются лениво: просто укажите имя трека при публикации, и он будет создан автоматически, если его еще нет.

Чтобы опубликовать превью в конкретном треке, используйте опцию `--track`:

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
> Доступ к превью имеют только люди с доступом к организации, которой принадлежит проект. Мы планируем добавить поддержку ссыпок с ограниченным сроком действия.

## Примечания к выпуску {#release-notes}

Используйте треки для групп окружений, а примечания к выпуску — для конкретной сборки:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Примечания к выпуску — это необязательный plain-текст длиной до 10 000 символов. Первая непустая строка отображается как однострочный фрагмент в веб- и iOS-списках превью, поэтому номера сборок и другая идентифицирующая информация видны сразу. Длинные строки обрезаются; полные примечания отображаются на страницах деталей. Поиск в обоих списках совпадает с отображаемыми именами и полными примечаниями к выпуску, включая строки, не показанные во фрагменте. Поддерживаются многострочные примечания, например `--release-notes "$(< release-notes.txt)"`. Они не меняют отображаемое имя приложения или его трек.

### Совместимость {#preview-metadata-compatibility}

Примечания к выпуску — это добавочные метаданные, а не часть идентичности превью. Загрузки от старых и новых клиентов по-прежнему группируются в одно превью на всех платформах. Сохраняются первые непустые примечания: последующая загрузка может заполнить отсутствовавшие ранее примечания, но не может перезаписать существующие. Пропуск `release_notes`, отправка `null` или отправка пустой строки либо строки, состоящей только из пробелов, никогда не очищает примечания. Существующие превью не заполняются ретроспективно и остаются действительными без примечаний.

Необязательный параметр запроса `track` API списка сопоставляет полное имя трека без учета регистра, что согласуется с текущим хранением треков. Опустите его или отправьте пустое значение (`?track=`), чтобы вывести все треки. Имена треков остаются произвольными строками, а не фиксированным списком значений. Выбор **Все треки** в iOS-приложении убирает фильтр. Таблетки треков в iOS-приложении загружают полную сводку проекта из `GET /api/projects/:account_handle/:project_handle/previews/tracks` с теми же правами на чтение превью, что и при перечислении сборок. Эта конечная точка возвращает `{total_count, tracks: [{name, count}]}` с отсортированными именованными треками, сгруппированными без учета регистра. Счетчики охватывают весь проект независимо от пагинации, поиска и выбранного трека; общая сумма включает превью без трека. Учитываются только перечисляемые превью с идентификатором пакета. API списка также принимает необязательный `search` для буквального подстрокового поиска без учета регистра в отображаемом имени или полных примечаниях к выпуску, комбинируемого с треком до пагинации. Существующая фильтрация по `display_name` остается точной.

Старые клиенты могут продолжать загружать и перечислять превью, не отправляя ни одного из этих полей. Новые клиенты принимают более старые ответы, в которых отсутствуют трек или примечания, и игнорируют неизвестные свойства ответа, добавленные будущими версиями сервера. Интеграции с API также должны игнорировать неизвестные свойства ответа, чтобы добавочные метаданные оставались совместимыми.

Для использования этих функций в self-hosted развертываниях требуется версия сервера, поддерживающая примечания к выпуску и фильтрацию по трекам, вместе с обновленными CLI и приложением. Более старые серверы могут игнорировать примечания или неизвестные параметры запроса. Если обнаружение треков недоступно, iOS-приложение сохраняет возможность просмотра без фильтра и объясняет, что выбор трека требует обновленного сервера. Если сервер возвращает превью из другого трека несмотря на активный фильтр, iOS-приложение сообщает, что фильтрация не поддерживается, вместо того чтобы показывать вводящие в заблуждение результаты. Приложение macOS сначала запрашивает последнее совместимое превью для каждого приложения; на более старых серверах, которые выбирают различные приложения до применения фильтров платформы, оно переключается на постраничную историю, не устанавливая отсечку, которая могла бы скрыть доступную сборку.

## Приложение Tuist для macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Чтобы запускать Tuist Previews было еще проще, мы разработали приложение Tuist для меню macOS. Вместо запуска превью через CLI Tuist вы можете [скачать](https://tuist.dev/download) приложение для macOS. Также вы можете установить приложение, выполнив `brew install --cask tuist/tuist/tuist`.

Когда вы нажимаете «Run» на странице превью, приложение для macOS автоматически запускает его на выбранном устройстве.

## Приложение Tuist для iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Скачать в App Store" style="height: 40px;">
    </a>
</div>

Как и приложение для macOS, приложение Tuist для iOS упрощает доступ к превью и их запуск. Каждое превью отображает свой трек. Используйте поле поиска, чтобы найти превью по имени приложения, затем выберите метку под **Треки**, чтобы отфильтровать по окружению. Выбранная метка становится фиолетовой; выберите **Все**, чтобы снять фильтр по трекам. Каждая метка показывает количество превью во всем проекте, а «Все» включает сборки без трека. Поиск и фильтрация по трекам применяются ко всем страницам, а не только к уже загруженным превью. Метка трека каждой сборки находится рядом с хешем коммита.

## Комментарии к pull/merge-запросам {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-платформой**
>
> Чтобы получать автоматические комментарии к pull/merge-запросам, интегрируйте ваш <.localized_link href="/guides/server/accounts-and-projects">удаленный проект</.localized_link> с <.localized_link href="/guides/server/authentication">Git-платформой</.localized_link>.

Тестирование нового функционала должно быть частью любого код-ревью. Но необходимость собирать приложение локально создает лишние препятствия, из-за чего разработчики часто вообще пропускают тестирование функционала на устройстве. А *что если бы каждый pull-запрос содержал ссылку на сборку, которая автоматически запускала бы приложение на устройстве, выбранном в приложении Tuist для macOS?*

После подключения вашего проекта Tuist к Git-платформе, такой как [GitHub](https://github.com), добавьте <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> в ваш CI-процесс. Tuist опубликует ссылку на превью прямо в ваших pull-запросах: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/github-app-with-preview.png)

## Уведомления об обновлениях внутри приложения {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) позволяет вашему приложению обнаруживать доступность новой версии превью и уведомлять пользователей. Это полезно для того, чтобы тестировщики всегда использовали последнюю сборку.

SDK проверяет обновления в пределах одного **трека превью**. Когда вы делитесь превью с явным указанием трека через `--track`, SDK будет искать обновления именно в этом треке. Если трек не указан, в качестве трека используется ветка git — поэтому превью, собранное из ветки `main`, будет уведомлять только о новых превью, также собранных из `main`.

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

### Единовременная проверка обновления {#sdk-single-check}

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

Чтобы сделать Tuist Previews более заметными в вашем репозитории, вы можете добавить бейдж в файл `README`, который указывает на последнее превью Tuist:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Чтобы добавить бейдж в ваш `README`, используйте следующий markdown и замените идентификаторы аккаунта и проекта на свои:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если ваш проект содержит несколько приложений с разными bundle identifiers, вы можете указать, превью какого приложения связать, добавив параметр запроса `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Автоматизации {#automations}

Вы можете использовать флаг `--json`, чтобы получить JSON-вывод команды `tuist share`:
```
tuist share --json
```

JSON-вывод полезен для создания пользовательских автоматизаций, например, отправки сообщения в Slack через ваш CI-провайдер. JSON содержит ключ `url` с полной ссылкой на превью и ключ `qrCodeURL` с URL изображения QR-кода, что упрощает скачивание превью с реального устройства. Пример JSON-вывода приведен ниже:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
