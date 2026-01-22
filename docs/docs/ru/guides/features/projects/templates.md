---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Шаблоны {#templates}

В проектах с установленной архитектурой разработчики могут захотеть запустить
новые компоненты или функции, которые соответствуют проекту. С помощью `tuist
scaffold` вы можете генерировать файлы из шаблона. Вы можете определить свои
собственные шаблоны или использовать те, которые поставляются с Tuist. Вот
несколько сценариев, в которых может быть полезно использование скелетов:

- Создайте новую функцию, следуя заданной архитектуре: `tuist scaffold viper
  --name MyFeature`.
- Создание новых проектов: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist не предъявляет никаких требований к содержанию ваших шаблонов и тому, для
чего вы их используете. Они должны находиться только в определенном каталоге.
<!-- -->
:::

## Определение шаблона {#defining-a-template}

Чтобы определить шаблоны, вы можете запустить
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>, а затем создать каталог с именем `name_of_template` в
`Tuist/Templates`, который представляет ваш шаблон. Шаблоны нуждаются в
манифест-файле `name_of_template.swift`, который описывает шаблон. Таким
образом, если вы создаете шаблон с именем `framework`, вам следует создать новый
каталог `framework` в `Tuist/Templates` с манифест-файлом `framework.swift`,
который может выглядеть следующим образом:


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

После определения шаблона мы можем использовать его из команды `scaffold`:

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
использовать язык шаблонов [Stencil](https://stencil.fuller.li/en/latest/) через
`.file` case. Кроме того, вы также можете использовать дополнительные фильтры,
определенные здесь.

Используя интерполяцию строк, `\(nameAttribute)` выше будет преобразовано в `{{
name }}`. Если вы хотите использовать фильтры Stencil в определении шаблона, вы
можете использовать эту интерполяцию вручную и добавить любые фильтры, которые
вам нравятся. Например, вы можете использовать `{ { name | lowercase } }` вместо
`\(nameAttribute)`, чтобы получить значение атрибута name в нижнем регистре.

Вы также можете использовать `.directory`, который дает возможность копировать
целые папки в заданный путь.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Шаблоны поддерживают использование
<LocalizedLink href="/guides/features/projects/code-sharing">помощников описания
проекта</LocalizedLink> для повторного использования кода в разных шаблонах.
<!-- -->
:::
