## Аналитика сборок в CI {#continuous-integration}

Чтобы отслеживать аналитику сборок в CI, убедитесь, что CI <.localized_link href="/guides/server/authentication#continuous-integration">аутентифицирован</.localized_link>.

Для CI на базе Xcodebuild необходимо:
- Используйте <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> при вызове действий `xcodebuild`.
- Добавьте `-resultBundlePath` в команду `xcodebuild`.

Без `-resultBundlePath` необходимые журналы активности и пакеты результатов не создаются, и `tuist inspect build` не может проанализировать сборку.
