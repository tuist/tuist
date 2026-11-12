## Análisis de compilaciones en CI {#continuous-integration}

Para rastrear los análisis de compilaciones en CI, asegúrate de que la CI esté <.localized_link href="/guides/server/authentication#continuous-integration">autenticada</.localized_link>.

Para una CI impulsada por Xcodebuild necesitas:
- Usa <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añade `-resultBundlePath` a tu comando de `xcodebuild`.

Sin `-resultBundlePath`, no se generan los registros de actividad ni los paquetes de resultados necesarios y `tuist inspect build` no puede analizar la compilación.
