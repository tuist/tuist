---
{
  "title": "Непрерывная интеграция",
  "titleTemplate": ":title · Swift · Package Registries · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist Registry в непрерывной интеграции."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Реестр работает «из коробки» в среде CI без дополнительной настройки аутентификации. По умолчанию для неаутентифицированных запросов установлено ограничение частоты: **1000 запросов в минуту** на один IP-адрес.

Если вам нужно более высокое ограничение — **20 000 запросов в минуту**, — вы можете пройти аутентификацию, выполнив команду `tuist registry login`. Для этого необходимо задать переменную окружения `TUIST_TOKEN`. Токен аккаунта можно создать, следуя <.localized_link href="/guides/server/authentication#account-tokens">руководству по аутентификации</.localized_link>.

> [!NOTE]
> Настройка связки ключей, описанная ниже, требуется только если вы используете `tuist registry login` для получения более высоких лимитов частоты запросов. В большинстве случаев стандартного неаутентифицированного лимита достаточно, и этот шаг можно полностью пропустить.
>
> Кроме того, создание новой предварительно разблокированной связки ключей необходимо только при использовании интеграции пакетов с Xcode.


Поскольку `tuist registry login` сохраняет учётные данные в связке ключей, нужно убедиться, что связка ключей доступна в среде CI. Обратите внимание: некоторые провайдеры CI или инструменты автоматизации, такие как [Fastlane](https://fastlane.tools/), уже создают временную связку ключей или предоставляют встроенный способ её создания. Однако вы также можете создать её, добавив пользовательский шаг со следующим кодом:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Убедитесь, что ваша связка ключей по умолчанию создана и разблокирована _до_ выполнения команды `tuist registry login`.

## Инкрементальное разрешение зависимостей между средами {#incremental-resolution-across-environments}

«Чистые»/«холодные» разрешения выполняются немного быстрее с нашим реестром, а ещё большего ускорения можно добиться, если сохранять разрешённые зависимости между сборками CI. Благодаря реестру размер каталога, который нужно сохранять и восстанавливать, значительно меньше, чем без реестра, поэтому процесс занимает гораздо меньше времени. Чтобы кэшировать зависимости при использовании стандартной интеграции пакетов Xcode, лучше всего указать пользовательский путь `clonedSourcePackagesDirPath` при разрешении зависимостей через `xcodebuild`. Это можно сделать, добавив следующее в файл `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
        )
    )
)
```

Кроме того, вам нужно найти путь к файлу `Package.resolved`. Его можно получить, выполнив команду `ls **/Package.resolved`. Путь должен выглядеть примерно так: `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Для Swift-пакетов и интеграции на основе XcodeProj можно использовать каталог `.build` по умолчанию, расположенный либо в корне проекта, либо в каталоге `Tuist`. Убедитесь, что путь указан верно при настройке вашего пайплайна.

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
