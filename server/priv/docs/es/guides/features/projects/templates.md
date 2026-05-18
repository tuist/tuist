---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Plantillas {#templates}

En proyectos con una arquitectura establecida, los desarrolladores pueden querer
arrancar nuevos componentes o características que sean consistentes con el
proyecto. Con `tuist scaffold` puedes generar archivos a partir de una
plantilla. Puedes definir tus propias plantillas o utilizar las que se venden
con Tuist. Estos son algunos escenarios en los que el andamiaje puede ser útil:

- Cree una nueva característica que siga una arquitectura determinada: `tuist
  scaffold viper --name MyFeature`.
- Crear nuevos proyectos: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Non-opinionated**
>
> Tuist no opina sobre el contenido de tus plantillas, ni para qué las utilizas.
> Sólo se requiere que estén en un directorio específico.


## Definir una plantilla {#defining-a-template}

Para definir plantillas, puede ejecutar
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> y luego crear un directorio llamado `name_of_template`
bajo `Tuist/Templates` que representa su plantilla. Las plantillas necesitan un
archivo de manifiesto, `name_of_template.swift` que describe la plantilla. Así
que si estás creando una plantilla llamada `framework`, deberías crear un nuevo
directorio `framework` en `Tuist/Templates` con un archivo de manifiesto llamado
`framework.swift` que podría tener este aspecto:


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

## Utilizar una plantilla {#using-a-template}

Una vez definida la plantilla, podemos utilizarla desde el comando `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Dado que la plataforma es un argumento opcional, también podemos llamar al
> comando sin el argumento `--platform macos`.


Si `.string` y `.files` no proporcionan suficiente flexibilidad, puede
aprovechar el lenguaje de plantillas
[Stencil](https://stencil.fuller.li/en/latest/) mediante el caso `.file`.
Además, también puede utilizar filtros adicionales definidos aquí.

Utilizando la interpolación de cadenas, `\(nombreAtributo)` anterior se
resolvería en `{{ nombre }}`. Si desea utilizar filtros Stencil en la definición
de la plantilla, puede utilizar esa interpolación manualmente y añadir los
filtros que desee. Por ejemplo, puede utilizar `{ { nombre | minúsculas } }` en
lugar de `\(nombreAtributo)` para obtener el valor en minúsculas del atributo
nombre.

También puede utilizar `.directory`, que ofrece la posibilidad de copiar
carpetas enteras en una ruta determinada.

> [!TIP]
> **Project Description Helpers**
>
> Las plantillas admiten el uso de
> <LocalizedLink href="/guides/features/projects/code-sharing">ayudantes de descripción de proyectos</LocalizedLink> para reutilizar código entre
> plantillas.

