---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Plantillas {#templates}

En proyectos con una arquitectura establecida, es posible que los
desarrolladores quieran iniciar nuevos componentes o características que sean
coherentes con el proyecto. Con `tuist scaffold` puedes generar archivos a
partir de una plantilla. Puedes definir tus propias plantillas o utilizar las
que se incluyen con Tuist. Estos son algunos casos en los que el scaffolding
puede resultar útil:

- Crea una nueva función que siga una arquitectura determinada: `tuist scaffold
  viper --name MyFeature`.
- Crear nuevos proyectos: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist no tiene ninguna opinión sobre el contenido de tus plantillas ni sobre el
uso que les des. Solo es necesario que se encuentren en un directorio
específico.
<!-- -->
:::

## Definición de una plantilla {#defining-a-template}

Para definir plantillas, puede ejecutar
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> y, a continuación, crear un directorio llamado
`nombre_de_la_plantilla` en `Tuist/Templates` que represente su plantilla. Las
plantillas necesitan un archivo de manifiesto, `nombre_de_la_plantilla.swift`
que describa la plantilla. Por lo tanto, si está creando una plantilla llamada
`framework`, debe crear un nuevo directorio `framework` en `Tuist/Templates` con
un archivo de manifiesto llamado `framework.swift` que podría tener este
aspecto:


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

## Uso de una plantilla {#using-a-template}

Una vez definida la plantilla, podemos utilizarla desde el comando « `» del
andamio «` »:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
Dado que la plataforma es un argumento opcional, también podemos llamar al
comando sin el argumento `--platform macos`.
<!-- -->
:::

Si `.string` y `.files` no ofrecen suficiente flexibilidad, puede aprovechar el
lenguaje de plantillas [Stencil](https://stencil.fuller.li/en/latest/) a través
del caso `.file`. Además, también puede utilizar filtros adicionales definidos
aquí.

Utilizando la interpolación de cadenas, `\(nameAttribute)` se resolvería como
`{{ name }}`. Si desea utilizar filtros Stencil en la definición de la
plantilla, puede utilizar esa interpolación manualmente y añadir los filtros que
desee. Por ejemplo, puede utilizar `{ { name | lowercase } }` en lugar de
`\(nameAttribute)` para obtener el valor en minúsculas del atributo name.

También puede utilizar `.directory`, que ofrece la posibilidad de copiar
carpetas completas a una ruta determinada.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Las plantillas admiten el uso de
<LocalizedLink href="/guides/features/projects/code-sharing">ayudas para la
descripción del proyecto</LocalizedLink> para reutilizar código en todas las
plantillas.
<!-- -->
:::
