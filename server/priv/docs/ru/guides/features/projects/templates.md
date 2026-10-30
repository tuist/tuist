---
{
  "title": "Шаблоны",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать шаблоны в Tuist для генерации кода в ваших проектах."
}
---
# Шаблоны {#templates}

В проектах с устоявшейся архитектурой разработчики могут захотеть быстро создать новые компоненты или возможности, соответствующие проекту. С помощью `tuist scaffold` вы можете генерировать файлы из шаблона. Вы можете определить собственные шаблоны или использовать те, что поставляются вместе с Tuist. Вот несколько сценариев, где шаблонизация может быть полезна:

- Создать новую возможность, соответствующую заданной архитектуре: `tuist scaffold viper --name MyFeature`.
- Создать новые проекты: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Без навязывания решений**
>
> Tuist не навязывает содержание ваших шаблонов и способы их использования. Единственное требование — они должны находиться в определённой директории.


## Определение шаблона {#defining-a-template}

Чтобы определить шаблоны, выполните <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>, а затем создайте директорию с именем `name_of_template` внутри `Tuist/Templates`, которая будет представлять ваш шаблон. Шаблонам необходим файл манифеста `name_of_template.swift`, описывающий шаблон. Например, если вы создаёте шаблон с именем `framework`, следует создать новую директорию `framework` в `Tuist/Templates` с файлом манифеста `framework.swift`, который может выглядеть так:


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
> Поскольку platform — необязательный аргумент, команду можно вызывать без аргумента `--platform macos`.


Если `.string` и `.files` не обеспечивают достаточной гибкости, вы можете воспользоваться языком шаблонов [Stencil](https://stencil.fuller.li/en/latest/) через вариант `.file`. Кроме того, можно использовать дополнительные фильтры, определённые здесь.

При использовании интерполяции строк выражение `\(nameAttribute)` выше преобразуется в `{{ name }}`. Если вы хотите использовать фильтры Stencil в определении шаблона, можно применить эту интерполяцию вручную и добавить любые нужные фильтры. Например, вместо `\(nameAttribute)` можно использовать `{ { name | lowercase } }`, чтобы получить значение атрибута name в нижнем регистре.

Также можно использовать `.directory`, что позволяет копировать целые папки по указанному пути.

> [!TIP]
> **Хелперы Project Description**
>
> Шаблоны поддерживают использование <.localized_link href="/guides/features/projects/code-sharing">хелперов Project Description</.localized_link> для повторного использования кода между шаблонами.
