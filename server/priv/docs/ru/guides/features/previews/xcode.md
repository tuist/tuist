---
{
  "title": "Предпросмотры Xcode",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Делитесь предпросмотрами приложений из существующих проектов Xcode и проектов, сгенерированных Tuist."
}
---
# Предпросмотры Xcode

Соберите приложение, затем используйте `tuist share`, чтобы опубликовать его в вашем проекте Tuist. Сначала подключите проект, следуя руководству по <.localized_link href="/guides/get-started/existing-xcode-project">существующему проекту Xcode</.localized_link> или <.localized_link href="/guides/get-started/generated-xcode-project">сгенерированному проекту</.localized_link>.

## Сборка и публикация

Для проекта, сгенерированного Tuist:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

Для существующего проекта Xcode:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

Замените названия схемы, проекта и рабочего пространства на свои. Чтобы поделиться сборкой Release, используйте `-configuration Release` при сборке и `--configuration Release` при публикации.

## Физические устройства

Вы несете ответственность за подписание сборок для устройств профилем обеспечения, который разрешает установку на устройство получателя. Выполняйте сборку с назначением на устройство вместо SDK симулятора:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

Вы также можете поделиться уже экспортированным IPA:

```bash
tuist share App.ipa
```

Получатели могут открыть ссылку предпросмотра IPA на своем мобильном устройстве, чтобы установить приложение. Аутентификация и настройки видимости предпросмотра проекта по-прежнему применяются.

## CI и номера сборок

Используйте вашу существующую <.localized_link href="/guides/integrations/continuous-integration">аутентификацию CI</.localized_link> и сделайте `CFBundleVersion` уникальным для каждой новой сборки. Например, используйте <code v-pre>${{ github.run_number }}</code> из GitHub Actions. Повторная загрузка того же бинарного файла и номера сборки через `tuist share` завершится ошибкой, а не создаст дубликат.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

См. <.localized_link href="/guides/features/previews#run-a-preview">Запуск предпросмотра</.localized_link> для информации о запуске опубликованных сборок, доступе, треках и бейджах для README.

<!-- @snippet: ./_tuist-share -->

Получатели могут использовать <.localized_link href="/guides/features/previews/run/macos">приложение Tuist для macOS</.localized_link> или <.localized_link href="/guides/features/previews/run/ios">приложение для iPhone</.localized_link> независимо от интеграции с системой сборки. Руководство для iPhone также охватывает <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">уведомления об обновлениях внутри приложения</.localized_link> с помощью Tuist SDK.
