---
{
  "title": "Динамическая конфигурация",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать переменные окружения для динамической настройки проекта."
}
---
# Динамическая конфигурация {#dynamic-configuration}

В некоторых сценариях может потребоваться динамически настраивать проект во время генерации. Например, вы можете захотеть изменить название приложения, идентификатор бандла или целевую версию развертывания в зависимости от окружения, в котором генерируется проект. Tuist поддерживает это через переменные окружения, которые можно читать из файлов манифеста.

## Конфигурация через переменные окружения {#configuration-through-environment-variables}

Tuist позволяет передавать конфигурацию через переменные окружения, доступные из файлов манифеста. Например:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Чтобы передать несколько переменных окружения, просто разделите их пробелом. Например:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Чтение переменных окружения из манифестов {#reading-the-environment-variables-from-manifests}

Переменные можно читать с помощью типа [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment). Любые переменные, соответствующие соглашению `TUIST_XXX` и определенные в окружении или переданные Tuist при запуске команд, будут доступны через тип `Environment`. Аксессоры используют имя переменной в camelCase без префикса `TUIST_`, поэтому `TUIST_APP_NAME` читается как `Environment.appName`, а `TUIST_ENABLE_ANALYTICS` — как `Environment.enableAnalytics`. Чтобы проверить, выполняется ли оценка манифеста в CI, используйте логическое значение `Environment.isCI`. В следующем примере читается `TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

При чтении переменных возвращается экземпляр типа `Environment.Value?`, который может принимать одно из следующих значений:

| Вариант | Описание |
| --- | --- |
| `.string(String)` | Используется, когда переменная представляет строку. |

Вы также можете получить строковую или булеву переменную `Environment` с помощью вспомогательных методов, описанных ниже. Эти методы требуют указания значения по умолчанию, чтобы пользователь каждый раз получал согласованные результаты. Это избавляет от необходимости определять функцию appName(), показанную выше.

::: code-group

```swift [String]
Environment.appName.getString(default: "MyApp")
```

```swift [Boolean]
Environment.enableAnalytics.getBoolean(default: false)
```
<!-- -->
:::

## Передача дополнительных переменных окружения в манифесты {#forwarding-additional-environment-variables-to-manifests}

По умолчанию в подпроцесс, который оценивает `Project.swift`, `Workspace.swift`, `Package.swift` и хелперы описания проекта, передаются только переменные с префиксом `TUIST_`, а также `CI` и `DEVELOPER_DIR`. Это делает генерацию детерминированной и предотвращает инвалидацию кэша манифестов из-за нерелевантных переменных оболочки или CI.

Если манифесту нужно читать переменные, которые вы не контролируете (например, сторонний `Package.swift`, который уже читает `OPENSWIFTUI_LIBRARY_TYPE`), объявите их в `Tuist.swift` через `manifestEnvironment` в опциях генерации. Каждая запись — это либо точное имя, либо имя, заканчивающееся на `*` для сопоставления по префиксу:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

Перечисленные переменные участвуют в хэше кэша манифестов, поэтому изменения их значений корректно инвалидируют кэш. Переменные, не включенные в список, остаются скрытыми при оценке манифеста.
