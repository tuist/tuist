---
{
  "title": "Xcode",
  "titleTemplate": ":title · Снимки · Возможности · Руководства · Tuist",
  "description": "Делайте снимки каждого предварительного просмотра SwiftUI в проекте Xcode и просматривайте изменения в Tuist."
}
---
# Снимки Xcode {#xcode-snapshots}

> [!IMPORTANT]
> **Требования**
>
> - Функция снимков включена для вашей учетной записи. Сейчас доступ предоставляется только по приглашению: [свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ.
> - Проект <.localized_link href="/guides/get-started/existing-xcode-project">подключен к Tuist</.localized_link>.
> - Для рендеринга превью требуется iOS 17 или macOS 14.

Библиотека [tuist/snapshots](https://github.com/tuist/snapshots) преобразует каждое SwiftUI-превью в вашем приложении в изображение, поэтому вам не нужно писать тесты снимков вручную. `tuist xcodebuild test` загружает изображения после запуска, а Tuist сравнивает их с <.localized_link href="/guides/features/snapshots#how-it-works">базовой версией</.localized_link>.

## Настройка {#set-up}

1. В Xcode добавьте пакет `https://github.com/tuist/snapshots`, начиная с версии `0.1.0`.
2. Создайте цель для модульных тестов, размещаемую вашим приложением, например `AppSnapshotTests`, и подключите к ней продукт пакета `TuistSnapshotsTesting`.
3. Добавьте класс тестов в эту цель. Каждое превью становится отдельным тестом:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. Добавьте схему, которая запускает эту цель, например `AppSnapshots`. Схема задает имя набора снимков.

## Запуск {#run}

Запускайте тесты через `tuist xcodebuild test`, всегда на одном и том же симуляторе, потому что на другом устройстве изображения будут иметь другой размер:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

В CI изображения, отрендеренные тестами, загружаются после запуска, и команда завершается ошибкой, если они изменились и никто не утвердил изменения. Локальные запуски ничего не загружают, так как это привело бы к загрузке незакоммиченных изменений.

<!-- @snippet: ./_previews-library -->
