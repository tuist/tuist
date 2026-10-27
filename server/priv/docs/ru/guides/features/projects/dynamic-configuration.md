---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Динамическая конфигурация {#dynamic-configuration}

Существуют определенные сценарии, в которых вам может потребоваться динамическая
настройка проекта во время генерации. Например, вы можете захотеть изменить имя
приложения, идентификатор пакета или цель развертывания в зависимости от среды,
в которой генерируется проект. Tuist поддерживает это с помощью переменных
окружения, доступ к которым можно получить из файлов манифеста.

## Конфигурирование с помощью переменных окружения {#configuration-through-environment-variables}

Tuist позволяет передавать конфигурацию через переменные окружения, доступ к
которым можно получить из файлов манифеста. Например:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Если вы хотите передать несколько переменных окружения, просто разделите их
пробелом. Например:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Чтение переменных окружения из манифестов {#reading-the-environment-variables-from-manifests}

Доступ к переменным осуществляется с помощью типа
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
Любые переменные, следующие соглашению `TUIST_XXX`, определенные в окружении или
переданные Tuist при выполнении команд, будут доступны с помощью типа
`Environment`. В следующем примере показано, как мы получаем доступ к переменной
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

| Дело              | Описание                                                  |
| ----------------- | --------------------------------------------------------- |
| `.string(String)` | Используется, когда переменная представляет собой строку. |

Вы также можете получить строку или булевую переменную `Environment` с помощью
одного из вспомогательных методов, определенных ниже. Эти методы требуют
передачи значения по умолчанию, чтобы пользователь каждый раз получал
последовательные результаты. Это избавляет от необходимости определять функцию
appName(), определенную выше.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
