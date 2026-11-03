---
{
  "title": "Запуск превью с приложением для iPhone",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Находите, фильтруйте и открывайте превью Apple с помощью приложения Tuist для iOS."
}
---
# Запуск превью через приложение для iPhone

Установите [приложение Tuist для iOS из App Store](https://apps.apple.com/us/app/tuist/id6748460335), чтобы находить и открывать ваши Apple-превью. Требования к подписи и совместимости устройств, действующие в процессе публикации, сохраняются.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Скачать в App Store" style="height: 40px;">
    </a>
</div>

Ищите по названию приложения или заметкам к релизу, затем выберите трек для фильтрации превью. Выберите **Все**, чтобы просмотреть все треки, включая превью без трека. Откройте превью, чтобы прочитать полные заметки к релизу.

## Совместимость клиента и сервера {#client-and-server-compatibility}

Поддерживайте приложение Tuist в актуальном состоянии. Если вы используете собственную инфраструктуру Tuist, обновите сервер, чтобы использовать фильтрацию по трекам и заметки к релизам. На старых версиях сервера можно просматривать превью без фильтрации.

## Уведомления об обновлениях внутри приложения {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) позволяет вашему приложению для Apple обнаруживать более новую версию превью и уведомлять тестировщиков. Проверка обновлений выполняется в рамках одного **трека превью**. Для превью, опубликованных с помощью `tuist share --track`, используется указанный трек. Если трек не указан явно, используется ветка git, поэтому превью, собранное из `main`, уведомляет только о новых превью из `main`.

### Установка {#sdk-installation}

Добавьте Tuist SDK как зависимость Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Мониторинг обновлений {#sdk-monitor-updates}

Используйте `monitorPreviewUpdates` для периодической проверки новых версий превью:

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

### Единоразовая проверка обновлений {#sdk-single-check}

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
