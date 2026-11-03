---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · Провайдеры CI · Раннеры · Возможности · Руководства · Tuist",
  "description": "Запустите свою первую задачу GitHub Actions на раннерах Tuist: подключите GitHub, укажите профиль Tuist в runs-on и отслеживайте выполнение в панели управления."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **Только по приглашению**
>
> Tuist Runners сейчас доступны только по приглашению. [Напишите нам](mailto:contact@tuist.dev) или обратитесь в [Slack‑сообществе](https://slack.tuist.dev), чтобы запросить доступ для вашего аккаунта.

Чтобы запустить задачу в кластере, нужно сделать три изменения: подключить GitHub, указать `runs-on` на <.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> Tuist и выполнить push.

1. **Запросите доступ.** Во время бета‑тестирования раннеры доступны только по приглашению. [Напишите нам](mailto:contact@tuist.dev), указав аккаунт, который нужно активировать.
2. **Подключите GitHub.** Убедитесь, что ваш проект <.localized_link href="/guides/integrations/gitforge/github">подключён к вашей организации GitHub</.localized_link>. Tuist получает события `workflow_job` для этой организации и направляет соответствующие задачи в кластер. Без этого подключения задачи не попадут на ваши раннеры.
3. **Укажите `runs-on` на профиль Tuist.** У каждого активированного аккаунта есть два готовых к использованию <.localized_link href="/guides/features/runners/profiles">профиля</.localized_link>: `linux` и `macos`. Ссылайтесь на них с префиксом `tuist-`:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Выбирайте Xcode через профиль раннера**
   >
   > Образ macOS‑раннера содержит одну версию Xcode, которую Tuist выбирает до начала задачи на основе профиля. Если вы переходите с раннеров GitHub, удалите шаги, использующие `xcode-select --switch` (или `xcode-select -s`), а также другие инструменты и действия для переключения версий Xcode. Такие шаги обычно опираются на установки Xcode, специфичные для образов GitHub, и могут завершиться ошибкой на Tuist Runners.
   >
   > Чтобы использовать другую версию Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">создайте или выберите профиль</.localized_link> с нужной версией и обновите `runs-on`, например `runs-on: tuist-xcode-26-4`. После этого `xcodebuild`, `xcrun` и `swift` будут использовать выбранную в профиле версию Xcode без дополнительной настройки в воркфлоу.

4. **Выполните push и наблюдайте.** Задача попадает в очередь, захватывается раннером, а её вывод передаётся в раздел **Runners** панели управления Tuist, где можно отслеживать логи, шаги и метрики машины.

## Кэш‑тома {#cache-volumes}

Сохраняйте кэши Xcode, модулей и Gradle, а также другие директории между задачами с помощью <.localized_link href="/guides/features/runners/cache-volumes">кэш‑томов</.localized_link>. Добавляйте их после checkout и перед командами, которые их используют.
