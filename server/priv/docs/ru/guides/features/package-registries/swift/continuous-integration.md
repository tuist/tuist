---
{
  "title": "Непрерывная интеграция",
  "titleTemplate": ":title · Swift · Package Registries · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist Registry в непрерывной интеграции."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Реестр работает в CI из коробки без дополнительной настройки аутентификации. По умолчанию для неаутентифицированных запросов установлено ограничение частоты: **1000 запросов в минуту** на один IP-адрес.

Если вам нужен более высокий лимит — **20 000 запросов в минуту**, — выполните аутентификацию, запустив `tuist registry login`. Для этого необходимо задать переменную окружения `TUIST_TOKEN`. Проектный токен можно создать, следуя документации <.localized_link href="/guides/server/authentication#as-a-project">здесь</.localized_link>.

> [!NOTE]
> Настройка связки ключей ниже требуется только если вы используете `tuist registry login` для получения более высоких лимитов частоты запросов. В большинстве случаев стандартного неаутентифицированного лимита достаточно, и этот шаг можно полностью пропустить.
>
> Кроме того, создание новой разблокированной связки ключей нужно только при использовании интеграции пакетов с Xcode.


Поскольку `tuist registry login` сохраняет учетные данные в связке ключей, убедитесь, что связка ключей доступна в среде CI. Обратите внимание: некоторые провайдеры CI или инструменты автоматизации, такие как [Fastlane](https://fastlane.tools/), уже создают временную связку ключей или предоставляют встроенный способ её создания. При необходимости вы можете создать её самостоятельно, добавив пользовательский шаг со следующим кодом:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Убедитесь, что стандартная связка ключей создана и разблокирована _до_ запуска `tuist registry login`.

### Инкрементальное разрешение зависимостей между средами {#incremental-resolution-across-environments}

«Чистое»/«холодное» разрешение зависимостей с нашим реестром происходит немного быстрее, а ещё большего ускорения можно добиться, сохраняя разрешённые зависимости между сборками в CI. Благодаря реестру размер каталога, который нужно сохранять и восстанавливать, значительно меньше, чем без реестра, поэтому процесс занимает гораздо меньше времени. Чтобы кэшировать зависимости при использовании стандартной интеграции пакетов Xcode, лучше всего указать пользовательский путь `clonedSourcePackagesDirPath` при разрешении зависимостей через `xcodebuild`. Для этого добавьте следующее в файл `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Кроме того, вам потребуется найти путь к файлу `Package.resolved`. Его можно получить, выполнив команду `ls **/Package.resolved`. Путь будет выглядеть примерно так: `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Для Swift-пакетов и интеграции на основе XcodeProj можно использовать стандартный каталог `.build`, расположенный либо в корне проекта, либо в каталоге `Tuist`. Убедитесь, что путь указан верно при настройке вашего пайплайна.

Ниже приведён пример рабочего процесса GitHub Actions для разрешения и кэширования зависимостей при использовании стандартной интеграции пакетов Xcode:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
