---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Чтобы использовать реестр в CI, необходимо убедиться, что вы вошли в реестр,
выполнив команду `tuist registry login` в рамках рабочего процесса.

::: info ONLY XCODE INTEGRATION
<!-- -->
Создание новой предварительно разблокированной связки ключей требуется только в
том случае, если вы используете интеграцию пакетов в Xcode.
<!-- -->
:::

Поскольку учетные данные реестра хранятся в связке ключей, необходимо убедиться,
что к этой связке можно получить доступ в среде CI. Обратите внимание, что
некоторые CI-провайдеры или инструменты автоматизации, например
[Fastlane](https://fastlane.tools/), уже создают временную связку ключей или
предоставляют встроенный способ ее создания. Однако вы также можете создать его,
создав пользовательский шаг со следующим кодом:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` сохранит учетные данные в связке ключей по умолчанию.
Убедитесь, что связка ключей по умолчанию создана и разблокирована _перед
запуском_ `tuist registry login`.

Кроме того, необходимо убедиться, что переменная окружения `TUIST_TOKEN`
установлена. Вы можете создать ее, следуя документации
<LocalizedLink href="/guides/server/authentication#as-a-project">здесь</LocalizedLink>.

Пример рабочего процесса для GitHub Actions может выглядеть следующим образом:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### Инкрементное разрешение в разных средах {#incremental-resolution-across-environments}

Чистое/холодное восстановление происходит немного быстрее с нашим реестром, и вы
можете получить еще большее улучшение, если будете сохранять разрешенные
зависимости во всех сборках CI. Обратите внимание, что благодаря реестру размер
директории, которую нужно хранить и восстанавливать, намного меньше, чем без
реестра, что занимает значительно меньше времени. Чтобы кэшировать зависимости
при использовании интеграции пакетов Xcode по умолчанию, лучше всего указать
пользовательский `clonedSourcePackagesDirPath` при разрешении зависимостей через
`xcodebuild`. Это можно сделать, добавив следующее в ваш `файл Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Кроме того, вам нужно найти путь к файлу `Package.resolved`. Вы можете найти
путь, выполнив команду `ls **/Package.resolved`. Путь должен выглядеть примерно
так `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Для пакетов Swift и интеграции на основе XcodeProj мы можем использовать каталог
по умолчанию `.build`, расположенный либо в корне проекта, либо в каталоге
`Tuist`. Убедитесь в правильности пути при настройке конвейера.

Вот пример рабочего процесса для GitHub Actions для разрешения и кэширования
зависимостей при использовании стандартной интеграции пакетов в Xcode:
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
