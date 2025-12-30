---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Шаблоны {#templates}

В проектах с устоявшейся архитектурой разработчики могут захотеть создать новые
компоненты или функции, которые будут соответствовать проекту. С помощью `tuist
scaffold` вы можете генерировать файлы на основе шаблона. Вы можете создать свои
собственные шаблоны или использовать те, которые поставляются вместе с Tuist.
Вот некоторые сценарии, в которых может быть полезен скаффолдинг:

- Создайте новую функцию, следующую заданной архитектуре: `tuist scaffold viper
  --name MyFeature`.
- Создание новых проектов: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist не придает значения содержанию ваших шаблонов и тому, для чего вы их
используете. Они обязаны находиться только в определенном каталоге.
<!-- -->
:::

## Определение шаблона {#defining-a-template}

Чтобы определить шаблоны, вы можете выполнить команду
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>, а затем создать каталог `name_of_template` в каталоге
`Tuist/Templates`, который представляет ваш шаблон. Шаблонам необходим файл
манифеста, `name_of_template.swift`, который описывает шаблон. Поэтому, если вы
создаете шаблон под названием `framework`, вам следует создать новую директорию
`framework` в `Tuist/Templates` с файлом манифеста `framework.swift`, который
может выглядеть следующим образом:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## Использование шаблона {#using-a-template}

Определив шаблон, мы можем использовать его с помощью команды `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
Поскольку платформа является необязательным аргументом, мы также можем вызвать
команду без аргумента `--platform macos`.
<!-- -->
:::

Если `.string` и `.files` не обеспечивают достаточной гибкости, вы можете
использовать язык шаблонов [Stencil](https://stencil.fuller.li/en/latest/) в
случае `.file`. Кроме того, вы можете использовать дополнительные фильтры,
определенные здесь.

Используя интерполяцию строк, `\(nameAttribute)` выше разрешится в `{{ name }}`.
Если вы хотите использовать фильтры Stencil в определении шаблона, вы можете
использовать эту интерполяцию вручную и добавить любые фильтры, которые вам
нравятся. Например, вы можете использовать `{ { { имя | строчная буква } }`
вместо `\(nameAttribute)`, чтобы получить значение атрибута name в нижнем
регистре.

Вы также можете использовать `.directory`, который дает возможность копировать
целые папки по заданному пути.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Шаблоны поддерживают использование
<LocalizedLink href="/guides/features/projects/code-sharing">помощников описания проекта</LocalizedLink> для повторного использования кода в шаблонах.
<!-- -->
:::
