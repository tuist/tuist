---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Снимки · Возможности · Руководства · Tuist",
  "description": "Делайте снимки каждого SwiftUI-превью в сгенерированном проекте Tuist и просматривайте изменения в Tuist."
}
---
# Снимки сгенерированного проекта Xcode {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **Требования**
>
> - Снимки включены для вашего аккаунта. Сейчас доступ только по приглашению: [свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ.
> - Проект <.localized_link href="/guides/get-started/generated-xcode-project">подключён к Tuist</.localized_link>.
> - iOS 17 или macOS 14 для рендеринга превью.

Библиотека [tuist/snapshots](https://github.com/tuist/snapshots) рендерит каждое SwiftUI-превью в вашем приложении в изображение, поэтому вам не нужно писать снимочные тесты вручную. `tuist test` загружает изображения после прогона, а Tuist сравнивает их с <.localized_link href="/guides/features/snapshots#how-it-works">базовой версией</.localized_link>.

## Настройка {#set-up}

Добавьте пакет в `Tuist/Package.swift`:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

Затем добавьте цель модульных тестов, которая зависит от вашего приложения и от `TuistSnapshotsTesting`, а также схему для её запуска. Схема задаёт имя набора снимков:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

Добавьте тестовый класс в цель. Каждое превью становится отдельным тестом:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

Выполните `tuist install`, чтобы получить пакет.

## Запуск {#run}

Запустите схему с помощью `tuist test`, всегда на одном и том же симуляторе, потому что другое устройство рендерит изображения другого размера:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

В CI изображения, отрендеренные тестами, загружаются после прогона, и команда завершается ошибкой, если они изменились и никто не одобрил изменения. Локальные прогоны ничего не загружают, потому что иначе они бы загружали незакоммиченные изменения.

> [!TIP]
> При <.localized_link href="/guides/features/selective-testing">выборочном тестировании</.localized_link> цель снимочных тестов пропускается только после того, как её изображения прошли проверку или были одобрены, поэтому повторный прогон не может пропустить цель, чьи изменения никто не ревьюил. Когда прогон пропускает цели, изображения, которые он не отрендерил, считаются пропущенными, а не удалёнными.

<!-- @snippet: ./_previews-library -->
