---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Archivos sintetizados {#synthesized-files}

Tuist puede generar archivos y código en el momento de la generación para
facilitar la gestión y el trabajo con proyectos Xcode. En esta página aprenderás
sobre esta funcionalidad y cómo puedes utilizarla en tus proyectos.

## Recursos de destino {#target-resources}

Los proyectos Xcode admiten la adición de recursos a los objetivos. Sin embargo,
plantean algunos retos a los equipos, especialmente cuando se trabaja con un
proyecto modular en el que las fuentes y los recursos se mueven con frecuencia:

- **Acceso inconsistente en tiempo de ejecución**: El lugar donde terminan los
  recursos en el producto final y la forma de acceder a ellos depende del
  producto de destino. Por ejemplo, si el destino es una aplicación, los
  recursos se copian al paquete de la aplicación. Esto hace que el código acceda
  a los recursos basándose en suposiciones sobre la estructura del paquete, lo
  que no es ideal porque dificulta la comprensión del código y el desplazamiento
  de los recursos.
- **Productos que no admiten recursos**: Hay ciertos productos, como las
  bibliotecas estáticas, que no son paquetes y, por lo tanto, no admiten
  recursos. Por eso, tendrás que recurrir a un tipo de producto diferente, por
  ejemplo, marcos de trabajo, lo que podría añadir cierta sobrecarga a tu
  proyecto o aplicación. Por ejemplo, los marcos estáticos se vincularán de
  forma estática al producto final, y se requiere una fase de compilación para
  copiar solo los recursos al producto final. O los marcos dinámicos, en los que
  Xcode copiará tanto el binario como los recursos al producto final, pero
  aumentará el tiempo de inicio de la aplicación porque el marco debe cargarse
  dinámicamente.
- **Propenso a errores de tiempo de ejecución**: Los recursos se identifican por
  su nombre y extensión (cadenas). Por lo tanto, un error tipográfico en
  cualquiera de ellos provocará un error de tiempo de ejecución al intentar
  acceder al recurso. Esto no es ideal porque no se detecta en tiempo de
  compilación y puede provocar fallos en el lanzamiento.

Tuist resuelve los problemas anteriores mediante **la síntesis de una interfaz
unificada para acceder a paquetes y recursos** que abstrae los detalles de
implementación.

::: warning RECOMMENDED
<!-- -->
Aunque no es obligatorio acceder a los recursos a través de la interfaz
sintetizada por Tuist, lo recomendamos porque facilita la comprensión del código
y el desplazamiento por los recursos.
<!-- -->
:::

## Recursos {#resources}

Tuist proporciona interfaces para declarar el contenido de archivos como
`Info.plist` o derechos en Swift. Esto es útil para garantizar la coherencia
entre los objetivos y los proyectos, y aprovechar el compilador para detectar
problemas en el momento de la compilación. También puede crear sus propias
abstracciones para modelar el contenido y compartirlo entre los objetivos y los
proyectos.

Cuando se genere tu proyecto, Tuist sintetizará el contenido de esos archivos y
los escribirá en el directorio `Derived` relativo al directorio que contiene el
proyecto que los define.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
Recomendamos añadir el directorio « `Derived» «` » al archivo « `.gitignore» «`
» de su proyecto.
<!-- -->
:::

## Accesores de paquetes {#bundle-accessors}

Tuist sintetiza una interfaz para acceder al paquete que contiene los recursos
de destino.

### Swift {#swift}

El destino contendrá una extensión del tipo `Bundle` que expone el paquete:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

En Objective-C, obtendrás una interfaz `{Target}Resources` para acceder al
paquete:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Actualmente, Tuist no genera accesores de paquetes de recursos para objetivos
internos que solo contienen fuentes Objective-C. Se trata de una limitación
conocida que se ha registrado en [issue
#6456](https://github.com/tuist/tuist/issues/6456).
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Si un producto de destino, por ejemplo una biblioteca, no admite recursos, Tuist
incluirá los recursos en un destino de tipo de producto `bundle` asegurándose de
que termine en el producto final y de que la interfaz apunte al paquete
correcto. Estos paquetes sintetizados se etiquetan automáticamente con
`tuist:synthesized` y heredan todas las etiquetas de su destino principal, lo
que le permite seleccionarlos en
<LocalizedLink href="/guides/features/projects/metadata-tags#system-tags">perfiles
de caché</LocalizedLink>.
<!-- -->
:::

## Accesores de recursos {#resource-accessors}

Los recursos se identifican por su nombre y extensión mediante cadenas. Esto no
es ideal, ya que no se detecta en tiempo de compilación y puede provocar fallos
en el lanzamiento. Para evitarlo, Tuist integra
[SwiftGen](https://github.com/SwiftGen/SwiftGen) en el proceso de generación del
proyecto para sintetizar una interfaz que permita acceder a los recursos.
Gracias a ello, puedes acceder con confianza a los recursos aprovechando el
compilador para detectar cualquier problema.

Tuist incluye
[plantillas](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
para sintetizar accesores para los siguientes tipos de recursos de forma
predeterminada:

| Tipo de recurso    | Sintetizado de ficheros    |
| ------------------ | -------------------------- |
| Imágenes y colores | `Assets+{Destino}.swift`   |
| Cadenas            | `Strings+{Target}.swift`   |
| Plists             | `{NombreDeLaLista}.swift`  |
| Fuentes            | `Fuentes+{Destino}.swift`  |
| Archivos           | `Archivos+{Destino}.swift` |

> Nota: Puede desactivar la síntesis de accesores de recursos por proyecto
> pasando la opción `disableSynthesizedResourceAccessors` a las opciones del
> proyecto.

#### Plantillas personalizadas {#custom-templates}

Si desea proporcionar sus propias plantillas para sintetizar accesores a otros
tipos de recursos, que deben ser compatibles con
[SwiftGen](https://github.com/SwiftGen/SwiftGen), puede crearlas en
`Tuist/ResourceSynthesizers/{name}.stencil`, donde el nombre es la versión en
mayúsculas y minúsculas del recurso.

| Recursos         | Nombre de la plantilla     |
| ---------------- | -------------------------- |
| cadenas          | `Strings.stencil`          |
| activos          | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| fuentes          | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| archivos         | `Archivos.plantilla`       |

Si desea configurar la lista de tipos de recursos para los que se sintetizarán
los accesores, puede utilizar la propiedad `Project.resourceSynthesizers`
pasando la lista de sintetizadores de recursos que desea utilizar:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Puedes consultar [este
ejemplo](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)
para ver cómo se utilizan las plantillas personalizadas para sintetizar
accesores a recursos.
<!-- -->
:::
