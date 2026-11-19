---
{
  "title": "Шаблоны",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать шаблоны в Tuist для генерации кода в ваших проектах."
}
---
# Шаблоны {#templates}

В проектах с устоявшейся архитектурой разработчики могут захотеть создать новые компоненты или возможности, соответствующие проекту. С помощью `tuist scaffold` вы можете генерировать файлы из шаблона. Вы можете определить свои собственные шаблоны или использовать те, которые поставляются с Tuist. Вот несколько сценариев, где использование шаблонов может быть полезно:

- Создать новую возможность, следующую заданной архитектуре: `tuist scaffold viper --name MyFeature`.
- Создать новые проекты: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Без навязывания мнения**
>
> Tuist не навязывает мнение о содержимом ваших шаблонов и том, для чего вы их используете. Единственное требование — они должны находиться в определённой директории.


## Определение шаблона {#defining-a-template}

Чтобы определить шаблоны, вы можете выполнить <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>, а затем создать директорию с именем `name_of_template` внутри `Tuist/Templates`, которая будет представлять ваш шаблон. Шаблонам необходим файл манифеста `name_of_template.swift`, описывающий шаблон. Таким образом, если вы создаёте шаблон с именем `framework`, вам следует создать новую директорию `framework` в `Tuist/Templates` с файлом манифеста `framework.swift`, который может выглядеть так:


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

После определения шаблона мы можем использовать его через команду `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Поскольку platform является необязательным аргументом, мы также можем вызвать команду без аргумента `--platform macos`.


Если `.string` и `.files` не обеспечивают достаточной гибкости, вы можете использовать язык шаблонов [Stencil](https://stencil.fuller.li/en/latest/) через вариант `.file`. Кроме того, вы можете использовать дополнительные фильтры, определённые здесь.

При использовании строковой интерполяции `\(nameAttribute)` выше будет преобразовано в `{{ name }}`. Если вы хотите использовать фильтры Stencil в определении шаблона, вы можете применить эту интерполяцию вручную и добавить любые нужные фильтры. Например, вы можете использовать `{ { name | lowercase } }` вместо `\(nameAttribute)`, чтобы получить значение атрибута name в нижнем регистре.

Вы также можете использовать `.directory`, что позволяет копировать целые папки по указанному пути.

> [!TIP]
> **Хелперы описания проекта**
>
> Шаблоны поддерживают использование <.localized_link href="/guides/features/projects/code-sharing">хелперов описания проекта</.localized_link> для повторного использования кода между шаблонами.
