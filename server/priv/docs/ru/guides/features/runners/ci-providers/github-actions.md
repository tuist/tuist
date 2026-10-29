---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first GitHub Actions job on Tuist Runners: connect GitHub, point runs-on at a Tuist profile, and watch it in the dashboard."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **Только по приглашению**
>
> Tuist Runners в настоящее время доступны только по приглашению. [Свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ для вашей учетной записи.

Для запуска задачи на кластере требуется три изменения: подключите GitHub, укажите `runs-on` в профиле Tuist <.localized_link href="/guides/features/runners/profiles"></.localized_link> и выполните push.

1. **Запросите доступ.** Во время бета-тестирования Runners доступны только по приглашению. [Свяжитесь с нами](mailto:contact@tuist.dev), указав учетную запись, которую нужно активировать.
2. **Подключите GitHub.** Убедитесь, что ваш проект <.localized_link href="/guides/integrations/gitforge/github">подключен к вашей организации GitHub</.localized_link>. Tuist получает события `workflow_job` для этой организации и направляет соответствующие задачи в кластер. Без этого подключения задачи не будут поступать на ваши раннеры.
3. **Укажите `runs-on` в профиле Tuist.** Каждая активированная учетная запись начинает работу с двумя готовыми к использованию <.localized_link href="/guides/features/runners/profiles">профилями</.localized_link>: `linux` и `macos`. Ссылайтесь на них с префиксом `tuist-`:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Выберите Xcode с помощью профиля раннера**
   >
   > Образ раннера macOS содержит одну версию Xcode, которую Tuist выбирает перед началом задачи на основе профиля. Если вы переходите с раннеров, размещенных на GitHub, удалите шаги, использующие `xcode-select --switch` (или `xcode-select -s`), а также другие инструменты и действия для переключения версий Xcode. Эти шаги обычно ссылается на установки Xcode, специфичные для образов, размещенных на GitHub, и могут завершиться ошибкой на Tuist Runners.
   >
   > Чтобы использовать другую версию Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">создайте или выберите профиль</.localized_link> с этой версией и обновите `runs-on`, например `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` и `swift` будут использовать выбранную в профиле версию Xcode без дополнительной настройки в рабочем процессе.

4. **Выполните push и наблюдайте.** Задача ставится в очередь, захватывается раннером, а ее данные передаются обратно в раздел **Runners** вашей панели управления Tuist, где вы можете отслеживать журналы, шаги и метрики машины.

## Кэширующие тома {#cache-volumes}

Сохраняйте кэши Xcode, модулей и Gradle, а также другие директории между задачами с помощью <.localized_link href="/guides/features/runners/cache-volumes">кэширующих томов</.localized_link>. Добавьте их после checkout и перед командами, которые их используют.
