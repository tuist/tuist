---
{
  "title": "Archivos sintetizados",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende sobre los archivos sintetizados en proyectos de Tuist."
}
---
# Archivos generados {#synthesized-files}

Tuist puede generar archivos y código durante la generación para facilitar la gestión y el trabajo con proyectos de Xcode. En esta página aprenderás sobre esta funcionalidad y cómo puedes usarla en tus proyectos.

## Recursos del target {#target-resources}

Los proyectos de Xcode permiten añadir recursos a los targets. Sin embargo, esto plantea algunos desafíos a los equipos, especialmente cuando se trabaja con un proyecto modular donde las fuentes y los recursos suelen moverse de lugar:

- **Acceso inconsistente en tiempo de ejecución**: Dónde acaban los recursos en el producto final y cómo accedes a ellos depende del tipo de producto del target. Por ejemplo, si tu target representa una aplicación, los recursos se copian al bundle de la aplicación. Esto lleva a que el código que accede a los recursos haga suposiciones sobre la estructura del bundle, lo cual no es ideal porque dificulta razonar sobre el código y mover los recursos.
- **Productos que no admiten recursos**: Hay ciertos productos, como las bibliotecas estáticas, que no son bundles y, por tanto, no admiten recursos. Debido a ello, debes recurrir a otro tipo de producto, por ejemplo frameworks, que podrían añadir cierta sobrecarga a tu proyecto o app. Por ejemplo, los frameworks estáticos se enlazarán estáticamente al producto final y se requiere una fase de compilación para copiar únicamente los recursos al producto final. O los frameworks dinámicos, donde Xcode copiará tanto el binario como los recursos al producto final, pero aumentará el tiempo de inicio de tu app porque el framework debe cargarse de forma dinámica.
- **Propenso a errores en tiempo de ejecución**: Los recursos se identifican por su nombre y extensión (cadenas). Por tanto, un error tipográfico en cualquiera de ellos provocará un error en tiempo de ejecución al intentar acceder al recurso. Esto no es ideal porque no se detecta en tiempo de compilación y podría provocar fallos en la versión de release.

Tuist resuelve los problemas anteriores **generando una interfaz unificada para acceder a bundles y recursos** que abstrae los detalles de implementación.

> [!WARNING]
> **Recomendado**
>
> Aunque acceder a los recursos a través de la interfaz generada por Tuist no es obligatorio, lo recomendamos porque facilita razonar sobre el código y mover los recursos.


## Recursos {#resources}

Tuist proporciona interfaces para declarar el contenido de archivos como `Info.plist` o entitlements en Swift. Esto es útil para garantizar la coherencia entre targets y proyectos, y aprovechar el compilador para detectar problemas en tiempo de compilación. También puedes crear tus propias abstracciones para modelar el contenido y compartirlo entre targets y proyectos.

Cuando se genera tu proyecto, Tuist sintetizará el contenido de esos archivos y los escribirá en el directorio `Derived` relativo al directorio que contiene el proyecto que los define.

> [!TIP]
> **Añade el directorio Derived al .gitignore**
>
> Recomendamos añadir el directorio `Derived` al archivo `.gitignore` de tu proyecto.


## Accesores de bundle {#bundle-accessors}

Tuist genera una interfaz para acceder al bundle que contiene los recursos del target.

### Swift {#swift}

El target incluirá una extensión del tipo `Bundle` que expone el bundle:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

En Objective-C, obtendrás una interfaz `{Target}Resources` para acceder al bundle:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **Limitación con targets internos**
>
> Actualmente, Tuist no genera accesores de bundle de recursos para targets internos que contienen únicamente fuentes en Objective-C. Esta es una limitación conocida registrada en [issue #6456](https://github.com/tuist/tuist/issues/6456).


> [!TIP]
> **Admitir recursos en bibliotecas mediante bundles**
>
> Si un producto de target, por ejemplo una biblioteca, no admite recursos, Tuist incluirá los recursos en un target de tipo de producto `bundle`, asegurando que acaben en el producto final y que la interfaz apunte al bundle correcto. Estos bundles generados se etiquetan automáticamente con `tuist:synthesized` y heredan todas las etiquetas de su target padre, lo que te permite dirigirlos en <.localized_link href="/guides/features/projects/metadata-tags#system-tags">perfiles de caché</.localized_link>.


## Accesores de recursos {#resource-accessors}

Los recursos se identifican por su nombre y extensión mediante cadenas. Esto no es ideal porque no se detecta en tiempo de compilación y podría provocar fallos en la versión de release. Para evitarlo, Tuist integra [SwiftGen](https://github.com/SwiftGen/SwiftGen) en el proceso de generación del proyecto para sintetizar una interfaz que permita acceder a los recursos. Gracias a ello, puedes acceder a los recursos con confianza aprovechando el compilador para detectar cualquier problema.

Tuist incluye [plantillas](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) para generar accesores para los siguientes tipos de recursos de forma predeterminada:

| Tipo de recurso | Archivo generado |
| --- | ---- |
| Imágenes y colores | `Assets+{Target}.swift` |
| Cadenas | `Strings+{Target}.swift` |
| Plists | `{NameOfPlist}.swift` |
| Fuentes | `Fonts+{Target}.swift` |
| Archivos | `Files+{Target}.swift` |

> Nota: Puedes desactivar la generación de accesores de recursos por proyecto pasando la opción `disableSynthesizedResourceAccessors` a las opciones del proyecto.

#### Plantillas personalizadas {#custom-templates}

Si quieres proporcionar tus propias plantillas para generar accesores a otros tipos de recursos, que deben ser compatibles con [SwiftGen](https://github.com/SwiftGen/SwiftGen), puedes crearlas en `Tuist/ResourceSynthesizers/{name}.stencil`, donde el nombre es la versión en camelCase del recurso.

| Recurso | Nombre de la plantilla |
| --- | --- |
| strings | `Strings.stencil` |
| assets | `Assets.stencil` |
| plists | `Plists.stencil` |
| fonts | `Fonts.stencil` |
| coreData | `CoreData.stencil` |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json | `JSON.stencil` |
| yaml | `YAML.stencil` |
| files | `Files.stencil` |

Si quieres configurar la lista de tipos de recursos para los que generar accesores, puedes usar la propiedad `Project.resourceSynthesizers` pasando la lista de sintetizadores de recursos que deseas utilizar:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **Referencia**
>
> Puedes consultar [este ejemplo](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates) para ver cómo usar plantillas personalizadas para generar accesores a los recursos.
