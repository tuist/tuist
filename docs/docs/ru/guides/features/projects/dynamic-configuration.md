---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Динамическая конфигурация {#dynamic-configuration}

В некоторых случаях может потребоваться динамическая настройка проекта во время
генерации. Например, вы можете захотеть изменить название приложения,
идентификатор пакета или цель развертывания в зависимости от среды, в которой
генерируется проект. Tuist поддерживает эту функцию с помощью переменных среды,
доступ к которым можно получить из файлов манифеста.

## Настройка через переменные окружения {#configuration-through-environment-variables}

Tuist позволяет передавать конфигурацию через переменные среды, доступные из
файлов манифеста. Например:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Если вы хотите передать несколько переменных окружения, просто разделите их
пробелом. Например:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Чтение переменных окружения из манифестов {#reading-the-environment-variables-from-manifests}

Доступ к переменным можно получить с помощью типа
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
Любые переменные, следующие соглашению `TUIST_XXX`, определенные в среде или
переданные Tuist при выполнении команд, будут доступны с помощью типа
`Environment`. Следующий пример показывает, как мы получаем доступ к переменной
`TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Доступ к переменным возвращает экземпляр типа `Environment.Value?`, который
может принимать любое из следующих значений:

| Регистр           | Описание                                                  |
| ----------------- | --------------------------------------------------------- |
| `.string(String)` | Используется, когда переменная представляет собой строку. |

Вы также можете получить строку или булево значение `Environment` с помощью
одного из вспомогательных методов, определенных ниже. Эти методы требуют
передачи значения по умолчанию, чтобы пользователь каждый раз получал одинаковые
результаты. Это позволяет избежать необходимости определять функцию appName(),
описанную выше.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
