---
{
  "title": "Шаблоны",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать шаблоны в Tuist для генерации кода в ваших проектах."
}
---
# Шаблоны {#templates}

В проектах с устоявшейся архитектурой разработчики могут захотеть создать новые компоненты или возможности, соответствующие проекту. С помощью `tuist scaffold` можно генерировать файлы из шаблона. Вы можете определить собственные шаблоны или использовать те, что поставляются вместе с Tuist. Вот несколько сценариев, где использование шаблонизации может быть полезно:

- Создать новую возможность, следующую заданной архитектуре: `tuist scaffold viper --name MyFeature`.
- Создать новые проекты: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Без навязывания подхода**
>
> Tuist не навязывает подход к содержимому ваших шаблонов и целям их использования. Единственное требование — они должны находиться в определённой директории.


## Определение шаблона {#defining-a-template}

Чтобы определить шаблоны, выполните <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>, затем создайте директорию с именем `name_of_template` внутри `Tuist/Templates`, которая будет представлять ваш шаблон. Для шаблонов требуется файл манифеста `name_of_template.swift`, описывающий шаблон. Например, если вы создаёте шаблон с именем `framework`, создайте новую директорию `framework` по пути `Tuist/Templates` с файлом манифеста `framework.swift`, который может выглядеть так:


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

После определения шаблона его можно использовать через команду `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Поскольку параметр platform является необязательным, команду можно вызывать без аргумента `--platform macos`.


Если `.string` и `.files` не обеспечивают достаточной гибкости, можно воспользоваться языком шаблонов [Stencil](https://stencil.fuller.li/en/latest/) через вариант `.file`. Кроме того, можно использовать дополнительные фильтры, описанные здесь.

При использовании интерполяции строк выражение `\(nameAttribute)` выше разрешится в `{{ name }}`. Если вы хотите использовать фильтры Stencil в определении шаблона, можно задать эту интерполяцию вручную и добавить любые нужные фильтры. Например, вместо `\(nameAttribute)` можно использовать `{ { name | lowercase } }`, чтобы получить значение атрибута name в нижнем регистре.

Также можно использовать `.directory`, что позволяет копировать целые папки по указанному пути.

> [!TIP]
> **Хелперы ProjectDescription**
>
> Шаблоны поддерживают использование <.localized_link href="/guides/features/projects/code-sharing">хелперов ProjectDescription</.localized_link> для повторного использования кода между шаблонами.
