---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Предварительные просмотры {#previews}

> [!ВАЖНЫЕ] ТРЕБОВАНИЯ
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет
>   и проект</LocalizedLink>

Создавая приложение, вы можете захотеть поделиться им с другими, чтобы получить
отзывы. Традиционно для этого команды создают, подписывают и отправляют свои
приложения на такие платформы, как [TestFlight] от Apple
(https://developer.apple.com/testflight/). Однако этот процесс может быть
громоздким и медленным, особенно если вы просто хотите получить быстрый отзыв от
коллеги или друга.

Чтобы сделать этот процесс более упорядоченным, Tuist предоставляет возможность
создавать предварительные версии ваших приложений и делиться ими с кем угодно.

> [!ВАЖНО] ПРИЛОЖЕНИЯ ДЛЯ УСТРОЙСТВ ДОЛЖНЫ БЫТЬ ПОДПИСАНЫ При сборке для
> устройства, в настоящее время вы несете ответственность за правильность
> подписи приложения. В будущем мы планируем упростить эту процедуру.

:::код-группа
```bash [Tuist Project]
tuist build App # Build the app for the simulator
tuist build App -- -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
:::

Команда сгенерирует ссылку, которой вы можете поделиться с кем угодно, чтобы
запустить приложение - либо на симуляторе, либо на реальном устройстве. Все, что
им нужно будет сделать, - это выполнить команду, приведенную ниже:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

При совместном использовании файла `.ipa` можно загрузить приложение
непосредственно с мобильного устройства, используя ссылку Preview. Ссылки на
предварительный просмотр `.ipa` по умолчанию _общедоступны_. В будущем у вас
будет возможность сделать их приватными, чтобы получателю ссылки нужно было
авторизоваться в своей учетной записи Tuist для загрузки приложения.

`tuist run` также позволяет запустить последнюю версию превью на основе такого
спецификатора, как `latest`, имени ветки или определенного хэша коммита:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!ВАЖНО] ВИДИМОСТЬ ПРЕДПРОЕКТОВ Только люди, имеющие доступ к организации, к
> которой принадлежит проект, могут получить доступ к превьюшкам. Мы планируем
> добавить поддержку ссылок с истекающим сроком действия.

## Приложение Tuist для macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Чтобы сделать запуск Tuist Preview еще проще, мы разработали приложение Tuist
для macOS. Вместо того чтобы запускать Previews через Tuist CLI, вы можете
[скачать](https://tuist.dev/download) приложение для macOS. Вы также можете
установить приложение, выполнив команду `brew install --cask tuist/tuist/tuist`.

Когда вы нажмете кнопку "Запустить" на странице предварительного просмотра,
приложение для macOS автоматически запустится на выбранном устройстве.

> [!ВАЖНЫЕ] ТРЕБОВАНИЯ
> 
> Вам необходимо иметь локально установленный Xcode и быть на macOS 14 или более
> поздней версии.

## Приложение Tuist для iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Как и приложение для macOS, приложение Tuist для iOS упрощает доступ к
предварительным просмотрам и их запуск.

## Комментарии к Pull/merge-запросам {#pullmerge-request-comments}

> [!ВАЖНО] ИНТЕГРАЦИЯ С GIT-ПЛАТФОРМОЙ ОБЯЗАТЕЛЬНА Для получения автоматических
> комментариев к запросам на вытягивание/слияние интегрируйте ваш
> <LocalizedLink href="/guides/server/accounts-and-projects">удаленный
> проект</LocalizedLink> с
> <LocalizedLink href="/guides/server/authentication">Git-платформой</LocalizedLink>.

Тестирование новой функциональности должно быть частью любого обзора кода. Но
необходимость собирать приложение локально добавляет ненужные трудности, что
часто приводит к тому, что разработчики вообще пропускают тестирование
функциональности на своем устройстве. Но *что, если бы каждый запрос на сборку
содержал ссылку на сборку, которая автоматически запускала бы приложение на
устройстве, выбранном в приложении Tuist macOS?*

Как только ваш проект Tuist будет связан с вашей Git-платформой, например
[GitHub](https://github.com), добавьте <LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink> в ваш рабочий процесс CI. После этого Tuist будет
публиковать ссылку на предварительный просмотр непосредственно в ваших запросах
на вытягивание: ![Комментарий приложения на GitHub со ссылкой на предварительный
просмотр Tuist](/images/guides/features/github-app-with-preview.png)

## Значок README {#readme-badge}

Чтобы сделать предварительные версии Tuist более заметными в вашем репозитории,
вы можете добавить в файл `README` значок, указывающий на последнюю
предварительную версию Tuist:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Чтобы добавить бейдж в свой `README`, используйте следующую разметку и замените
учетные записи и названия проектов на свои:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если ваш проект содержит несколько приложений с разными идентификаторами
пакетов, вы можете указать, на какой предварительный просмотр приложения следует
ссылаться, добавив параметр запроса `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Автоматизации {#automations}

Вы можете использовать флаг `--json`, чтобы получить вывод в формате JSON от
команды `tuist share`:
```
tuist share --json
```

Вывод JSON полезен для создания пользовательских автоматизаций, таких как
отправка сообщения в Slack с помощью вашего CI-провайдера. JSON содержит ключ
`url` с полной ссылкой на превью и ключ `qrCodeURL` с URL-адресом изображения
QR-кода, чтобы упростить загрузку превью с реального устройства. Пример вывода
JSON приведен ниже:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
