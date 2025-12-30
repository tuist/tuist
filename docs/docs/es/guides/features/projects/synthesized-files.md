---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Archivos sintetizados {#synthesized-files}

Tuist puede generar archivos y código en tiempo de generación para aportar algo
de comodidad a la gestión y el trabajo con proyectos Xcode. En esta página
aprenderás sobre esta funcionalidad y cómo puedes utilizarla en tus proyectos.

## Recursos {#target-resources}

Los proyectos Xcode permiten añadir recursos a los objetivos. Sin embargo,
plantean algunos retos a los equipos, sobre todo cuando se trabaja con un
proyecto modular en el que las fuentes y los recursos se desplazan con
frecuencia:

- **Acceso incoherente en tiempo de ejecución**: La ubicación de los recursos en
  el producto final y la forma de acceder a ellos dependen del producto de
  destino. Por ejemplo, si tu objetivo representa una aplicación, los recursos
  se copian en el paquete de la aplicación. Esto lleva a que el código que
  accede a los recursos haga suposiciones sobre la estructura del paquete, lo
  que no es ideal porque hace que el código sea más difícil de razonar y que los
  recursos se muevan de un lado a otro.
- **Productos que no admiten recursos**: Hay ciertos productos como las
  librerías estáticas que no son paquetes y por lo tanto no soportan recursos.
  Debido a esto, tienes que recurrir a un tipo de producto diferente, por
  ejemplo frameworks, que pueden añadir algo de sobrecarga a tu proyecto o
  aplicación. Por ejemplo, los frameworks estáticos se enlazarán estáticamente
  al producto final, y será necesaria una fase de compilación para copiar
  únicamente los recursos al producto final. O frameworks dinámicos, donde Xcode
  copiará tanto el binario como los recursos en el producto final, pero
  aumentará el tiempo de arranque de tu aplicación porque el framework necesita
  cargarse dinámicamente.
- **Propenso a errores de ejecución**: Los recursos se identifican por su nombre
  y extensión (cadenas). Por lo tanto, una errata en cualquiera de ellos
  provocará un error en tiempo de ejecución al intentar acceder al recurso. Esto
  no es lo ideal porque no se detecta en tiempo de compilación y puede provocar
  fallos en la versión.

Tuist resuelve los problemas anteriores sintetizando en **una interfaz unificada
para acceder a paquetes y recursos** que abstrae los detalles de implementación.

::: warning RECOMMENDED
<!-- -->
Aunque acceder a los recursos a través de la interfaz sintetizada por Tuist no
es obligatorio, lo recomendamos porque facilita el razonamiento sobre el código
y la movilidad de los recursos.
<!-- -->
:::

## Recursos {#resources}

Tuist proporciona interfaces para declarar el contenido de archivos como
`Info.plist` o derechos en Swift. Esto es útil para garantizar la coherencia
entre objetivos y proyectos, y aprovechar el compilador para detectar problemas
en tiempo de compilación. También puedes crear tus propias abstracciones para
modelar el contenido y compartirlo entre objetivos y proyectos.

Cuando se genere tu proyecto, Tuist sintetizará el contenido de esos archivos y
los escribirá en el directorio `Derived` relativo al directorio que contiene el
proyecto que los define.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
Le recomendamos que añada el directorio `Derived` al archivo `.gitignore` de su
proyecto.
<!-- -->
:::

## Accesorios del paquete {#bundle-accessors}

Tuist sintetiza una interfaz para acceder al paquete que contiene los recursos
de destino.

### Swift {#swift}

El objetivo contendrá una extensión del tipo `Bundle` que expone el bundle:

```swift
let bundle = Bundle.module
```

### Objetivo-C {#objectivec}

En Objective-C, obtendrá una interfaz `{Target}Resources` para acceder al
bundle:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Actualmente, Tuist no genera accesores de paquetes de recursos para objetivos
internos que contienen sólo fuentes Objective-C. Se trata de una limitación
conocida de la que se hace un seguimiento en [issue
#6456](https://github.com/tuist/tuist/issues/6456).
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Si un producto de destino, por ejemplo una biblioteca, no admite recursos, Tuist
incluirá los recursos en un destino del tipo de producto `bundle` asegurándose
de que acaba en el producto final y de que la interfaz apunta al bundle
correcto.
<!-- -->
:::

## Accesores de recursos {#resource-accessors}

Los recursos se identifican por su nombre y extensión mediante cadenas. Esto no
es lo ideal porque no se detecta en tiempo de compilación y puede provocar
fallos en la versión. Para evitarlo, Tuist integra
[SwiftGen](https://github.com/SwiftGen/SwiftGen) en el proceso de generación del
proyecto para sintetizar una interfaz de acceso a los recursos. Gracias a eso,
puedes acceder con confianza a los recursos aprovechando el compilador para
detectar cualquier problema.

Tuist incluye
[plantillas](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
para sintetizar por defecto accesores para los siguientes tipos de recursos:

| Tipo de recurso    | Sintetizado de ficheros     |
| ------------------ | --------------------------- |
| Imágenes y colores | `Activos+{Objetivo}.swift`  |
| Cuerdas            | `Cadenas+{Objetivo}.swift`  |
| Listas             | `{NombreDeLista}.swift`     |
| Fuentes            | `Fuentes+{Target}.swift`    |
| Archivos           | `Archivos+{Objetivo}.swift` |

> Nota: Puede desactivar la sintetización de accesores de recursos por proyecto
> pasando la opción `disableSynthesizedResourceAccessors` a las opciones del
> proyecto.

#### Plantillas personalizadas {#custom-templates}

Si quieres proporcionar tus propias plantillas para sintetizar accesores a otros
tipos de recursos, que deben ser soportados por
[SwiftGen](https://github.com/SwiftGen/SwiftGen), puedes crearlas en
`Tuist/ResourceSynthesizers/{nombre}.stencil`, donde el nombre es la versión en
camel-case del recurso.

| Recursos         | Nombre de la plantilla     |
| ---------------- | -------------------------- |
| cadenas          | `Strings.stencil`          |
| activos          | `Activos.stencil`          |
| plists           | `Plists.stencil`           |
| fuentes          | `Fuentes.stencil`          |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| archivos         | `Archivos.stencil`         |

Si desea configurar la lista de tipos de recursos para los que sintetizar los
accesores, puede utilizar la propiedad `Project.resourceSynthesizers` pasando la
lista de sintetizadores de recursos que desea utilizar:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Puedes consultar [this
fixture](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)
para ver un ejemplo de cómo utilizar plantillas personalizadas para sintetizar
accesores a recursos.
<!-- -->
:::
