---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · Провайдеры CI · Раннеры · Возможности · Руководства · Tuist",
  "description": "Запустите свой первый job GitHub Actions на раннерах Tuist: подключите GitHub, укажите профиль Tuist в runs-on и наблюдайте за процессом в панели управления."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

Чтобы запустить задачу в пуле, нужно сделать три изменения: подключить GitHub, указать `runs-on` на <.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> Tuist и отправить изменения.

1. **Подключите GitHub.** Убедитесь, что ваш проект <.localized_link href="/guides/integrations/gitforge/github">подключён к вашей организации GitHub</.localized_link>. Tuist получает события `workflow_job` для этой организации и направляет соответствующие задачи в пул. Без этого подключения задачи не попадут на ваши раннеры.
2. **Укажите `runs-on` на профиль Tuist.** Каждая активированная учётная запись начинается с двух готовых к использованию <.localized_link href="/guides/features/runners/profiles">профилей</.localized_link>: `linux` и `macos`. Ссылайтесь на них с префиксом `tuist-`:

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
   > Образ раннера macOS содержит одну версию Xcode, которую Tuist выбирает до начала задачи на основе профиля. Если вы переходите с раннеров, размещённых на GitHub, удалите шаги, использующие `xcode-select --switch` (или `xcode-select -s`), а также другие инструменты и действия для переключения версий Xcode. Эти шаги обычно ссылается на установки Xcode, специфичные для образов GitHub, и могут завершиться ошибкой на раннерах Tuist.
   >
   > Чтобы использовать другую версию Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">создайте или выберите профиль</.localized_link> с этой версией и обновите `runs-on`, например `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` и `swift` будут использовать выбранную в профиле версию Xcode без дополнительной настройки в рабочем процессе.

3. **Отправьте изменения и наблюдайте.** Задача ставится в очередь, захватывается раннером, а её логи, шаги и метрики машины транслируются обратно в раздел **Runners** вашей панели управления Tuist.

## Кэширующие тома {#cache-volumes}

Сохраняйте кэши Xcode, модулей и Gradle, а также другие директории между задачами с помощью <.localized_link href="/guides/features/runners/cache-volumes">кэширующих томов</.localized_link>. Добавляйте их после клонирования репозитория и перед командами, которые их используют.

Предоставьте задаче разрешение `id-token: write`, чтобы её кэширующие тома и закэшированное клонирование подключались сразу при запуске. Без этого раннер ждёт, пока GitHub сообщит, какую задачу он выполняет, и задача, о которой GitHub сообщает с задержкой, запускается с пустыми кэшами. Рабочий процесс, который входит в Tuist через OpenID Connect, уже предоставляет это разрешение.

```yaml
permissions:
  contents: read
  id-token: write
```
