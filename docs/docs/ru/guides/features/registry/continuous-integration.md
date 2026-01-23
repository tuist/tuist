---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Непрерывная интеграция (CI) {#continuous-integration-ci}

Чтобы использовать реестр в вашей CI, вам необходимо убедиться, что вы вошли в
реестр, запустив `tuist registry login` в рамках вашего рабочего процесса.

::: info ONLY XCODE INTEGRATION
<!-- -->
Создание нового предварительно разблокированного ключа требуется только в том
случае, если вы используете интеграцию пакетов Xcode.
<!-- -->
:::

Поскольку учетные данные реестра хранятся в брелоке, необходимо убедиться, что
брелок доступен в среде CI. Обратите внимание, что некоторые поставщики CI или
инструменты автоматизации, такие как [Fastlane](https://fastlane.tools/), уже
создают временный брелок или предоставляют встроенный способ его создания.
Однако вы также можете создать его, создав настраиваемый шаг со следующим кодом:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` затем сохранит учетные данные в стандартном брелоке.
Убедитесь, что ваш стандартный брелок создан и разблокирован _перед запуском_
`tuist registry login`.

Кроме того, необходимо убедиться, что установлена переменная среды
`TUIST_TOKEN`. Вы можете создать ее, следуя инструкциям
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

### Постепенное разрешение в разных средах {#incremental-resolution-across-environments}

Чистые/холодные разрешения работают немного быстрее с нашим реестром, и вы
можете добиться еще большего улучшения, если сохраните разрешенные зависимости в
сборках CI. Обратите внимание, что благодаря реестру размер каталога, который
необходимо хранить и восстанавливать, намного меньше, чем без реестра, что
значительно сокращает время. Чтобы кэшировать зависимости при использовании
интеграции пакетов Xcode по умолчанию, лучший способ — указать настраиваемый
`clonedSourcePackagesDirPath` при разрешении зависимостей через `xcodebuild`.
Это можно сделать, добавив следующее в файл `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Кроме того, вам нужно будет найти путь к пакету `Package.resolved`. Вы можете
получить этот путь, запустив `ls **/Package.resolved`. Путь должен выглядеть
примерно так:
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Для пакетов Swift и интеграции на основе XcodeProj мы можем использовать
стандартный каталог `.build`, расположенный либо в корневом каталоге проекта,
либо в каталоге `Tuist`. Убедитесь, что путь указан правильно при настройке
конвейера.

Вот пример рабочего процесса GitHub Actions для разрешения и кэширования
зависимостей при использовании интеграции пакета Xcode по умолчанию:
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
