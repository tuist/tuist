---
{
  "title": "Plantillas",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a crear y usar plantillas en Tuist para generar código en tus proyectos."
}
---
# Plantillas {#templates}

En proyectos con una arquitectura establecida, los desarrolladores pueden querer inicializar nuevos componentes o funcionalidades que sean coherentes con el proyecto. Con `tuist scaffold` puedes generar archivos a partir de una plantilla. Puedes definir tus propias plantillas o usar las que vienen incluidas con Tuist. Estos son algunos escenarios en los que el scaffolding puede ser útil:

- Crear una nueva funcionalidad que siga una arquitectura determinada: `tuist scaffold viper --name MyFeature`.
- Crear nuevos proyectos: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **Sin opiniones predefinidas**
>
> Tuist no impone opiniones sobre el contenido de tus plantillas ni sobre su uso. Solo se requiere que estén en un directorio específico.


## Definir una plantilla {#defining-a-template}

Para definir plantillas, puedes ejecutar <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> y luego crear un directorio llamado `name_of_template` dentro de `Tuist/Templates` que represente tu plantilla. Las plantillas necesitan un archivo de manifiesto, `name_of_template.swift`, que describe la plantilla. Por lo tanto, si estás creando una plantilla llamada `framework`, deberías crear un nuevo directorio `framework` en `Tuist/Templates` con un archivo de manifiesto llamado `framework.swift` que podría verse así:


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

## Usar una plantilla {#using-a-template}

Después de definir la plantilla, podemos usarla desde el comando `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Dado que platform es un argumento opcional, también podemos llamar al comando sin el argumento `--platform macos`.


Si `.string` y `.files` no ofrecen suficiente flexibilidad, puedes aprovechar el lenguaje de plantillas [Stencil](https://stencil.fuller.li/en/latest/) mediante el caso `.file`. Además, también puedes usar filtros adicionales definidos aquí.

Con interpolación de cadenas, `\(nameAttribute)` anterior se resolvería como `{{ name }}`. Si deseas usar filtros de Stencil en la definición de la plantilla, puedes usar esa interpolación manualmente y añadir los filtros que prefieras. Por ejemplo, podrías usar `{ { name | lowercase } }` en lugar de `\(nameAttribute)` para obtener el valor en minúsculas del atributo name.

También puedes usar `.directory`, que permite copiar carpetas completas a una ruta determinada.

> [!TIP]
> **Ayudantes de ProjectDescription**
>
> Las plantillas admiten el uso de <.localized_link href="/guides/features/projects/code-sharing">ayudantes de ProjectDescription</.localized_link> para reutilizar código entre plantillas.
