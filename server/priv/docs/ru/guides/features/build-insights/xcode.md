---
{
  "title": "Аналитика сборок Xcode",
  "titleTemplate": ":title · Аналитика сборок · Возможности · Руководства · Tuist",
  "description": "Отслеживайте аналитику сборок Xcode в панели управления Tuist, чтобы контролировать производительность локальных сборок и сборок в CI."
}
---
# Аналитика сборок Xcode {#xcode-build-insights}

Работа над крупными проектами не должна требовать многократной пересборки одного и того же кода. Tuist Build Insights позволяет отслеживать аналитику сборок, чтобы вы могли выявлять тенденции до того, как время локальных сборок и сборок в CI станет узким местом.

Аналитика сборок формируется командой `tuist inspect build`, которую обычно добавляют в пост-действие схемы.

Чтобы начать отслеживать время локальных сборок, используйте команду `tuist inspect build`, добавив её в пост-действие схемы:

![Пост-действие для анализа сборок](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Установите поле «Provide build settings from» на исполняемый файл или ваш основной таргет сборки, чтобы захватить конфигурацию сборки.

> [!NOTE]
> Пост-действие схемы не выполняется, если сборка завершилась ошибкой.
>
> В этом случае вы можете выполнить его, установив `runPostActionsOnFailure` в значение `YES` для элемента `<BuildAction>` в файле схемы `.xcscheme`:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Для [Mise](https://mise.jdx.dev/) активируйте `tuist` в окружении пост-действия:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Разрешение пути Mise**
>
> Переменная `PATH` вашего окружения не наследуется пост-действием схемы, поэтому используйте абсолютный путь к Mise. Он зависит от способа установки Mise. Настройки сборки должны наследоваться от таргета, чтобы `mise` мог выполняться из `$SRCROOT`.

Для [Homebrew](https://brew.sh/) добавьте пути Homebrew в окружение пост-действия:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

После входа в систему локальные сборки отслеживаются и доступны в панели управления Tuist:

> [!TIP]
> Чтобы быстро открыть панель управления, выполните `tuist project show --web` в CLI.

![Панель управления с аналитикой сборок](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
