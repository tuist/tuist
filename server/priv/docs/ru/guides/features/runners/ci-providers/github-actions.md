---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Запустите свой первый job GitHub Actions на раннерах Tuist: подключите GitHub, укажите профиль Tuist в runs-on и отслеживайте выполнение в панели управления."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

Чтобы запустить задачу в кластере, нужно сделать три изменения: подключить GitHub, указать `runs-on` на <.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> Tuist и выполнить push.

1. **Подключите GitHub.** Убедитесь, что ваш проект <.localized_link href="/guides/integrations/gitforge/github">подключён к вашей организации GitHub</.localized_link>. Tuist получает события `workflow_job` для этой организации и направляет соответствующие задачи в кластер. Без этого подключения задачи не попадут на ваши раннеры.
2. **Укажите `runs-on` на профиль Tuist.** Каждая активированная учётная запись начинает работу с двумя готовыми к использованию <.localized_link href="/guides/features/runners/profiles">профилями</.localized_link>: `linux` и `macos`. Ссылайтесь на них с префиксом `tuist-`:

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
   > Образ раннера macOS содержит одну версию Xcode, которую Tuist выбирает до начала задачи на основе профиля. Если вы переходите с раннеров, размещённых на GitHub, удалите шаги, использующие `xcode-select --switch` (или `xcode-select -s`), а также другие инструменты и действия для переключения версий Xcode. Эти шаги обычно ссылаются на установки Xcode, специфичные для образов GitHub, и могут завершаться ошибкой на раннерах Tuist.
   >
   > Чтобы использовать другую версию Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">создайте или выберите профиль</.localized_link> с этой версией и обновите `runs-on`, например `runs-on: tuist-xcode-26-4`. После этого `xcodebuild`, `xcrun` и `swift` будут использовать выбранную в профиле версию Xcode без дополнительной настройки в рабочем процессе.

3. **Выполните push и наблюдайте.** Задача ставится в очередь, захватывается раннером, а её логи, шаги и метрики машины транслируются обратно в раздел **Раннеры** вашего дашборда Tuist.

## Кэш-тома {#cache-volumes}

Сохраняйте кэши Xcode, модулей и Gradle, а также другие директории между задачами с помощью <.localized_link href="/guides/features/runners/cache-volumes">кэш-томов</.localized_link>. Добавляйте их после checkout и перед командами, которые их используют.

Предоставьте задаче разрешение `id-token: write`, чтобы её кэш-тома и закэшированный checkout подключались сразу при запуске. Без этого раннер ждёт, пока GitHub сообщит, какую задачу он выполняет, и задача, о которой GitHub сообщает с задержкой, запускается с пустыми кэшами. Рабочий процесс, который входит в Tuist через OpenID Connect, уже предоставляет это разрешение.

```yaml
permissions:
  contents: read
  id-token: write
```
