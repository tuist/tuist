---
{
  "title": "Dependencias",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a declarar dependencias en tu proyecto de Tuist."
}
---
# Dependencias {#dependencies}

Cuando un proyecto crece, es habitual dividirlo en varios targets para compartir código, definir límites y mejorar los tiempos de compilación. Tener varios targets implica definir dependencias entre ellos, formando un **grafo de dependencias**, que también puede incluir dependencias externas.

## Grafos codificados en XcodeProj {#xcodeprojcodified-graphs}

Debido al diseño de Xcode y XcodeProj, el mantenimiento de un grafo de dependencias puede ser una tarea tediosa y propensa a errores. A continuación se muestran algunos ejemplos de los problemas que podrías encontrar:

- Como el sistema de compilación de Xcode coloca todos los productos del proyecto en el mismo directorio dentro de los datos derivados, los targets podrían importar productos que no deberían. Las compilaciones podrían fallar en CI, donde las compilaciones limpias son más habituales, o más adelante al usar una configuración diferente.
- Las dependencias dinámicas transitivas de un target deben copiarse en cualquiera de los directorios que forman parte de la configuración de compilación `LD_RUNPATH_SEARCH_PATHS`. Si no lo están, el target no podrá encontrarlas en tiempo de ejecución. Esto es fácil de considerar y configurar cuando el grafo es pequeño, pero se convierte en un problema a medida que el grafo crece.
- Cuando un target enlaza un [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) estático, necesita una fase de compilación adicional para que Xcode procese el bundle y extraiga el binario correcto para la plataforma y arquitectura actuales. Esta fase de compilación no se añade automáticamente y es fácil olvidar agregarla.

Los anteriores son solo algunos ejemplos, pero hay muchos más que hemos encontrado a lo largo de los años. Imagina si necesitaras un equipo de ingenieros para mantener un grafo de dependencias y garantizar su validez. O, peor aún, que esas complejidades se resolvieran en tiempo de compilación mediante un sistema de compilación de código cerrado que no puedes controlar ni personalizar. ¿Te resulta familiar? Este es el enfoque que Apple adoptó con Xcode y XcodeProj y que ha heredado Swift Package Manager.

Creemos firmemente que el grafo de dependencias debe ser **explícito** y **estático**, porque solo así puede ser **validado** y **optimizado**. Con Tuist, te centras en describir qué depende de qué y nosotros nos encargamos del resto. Las complejidades y los detalles de implementación quedan abstraídos para ti.

En las siguientes secciones aprenderás cómo declarar dependencias en tu proyecto.

> [!TIP]
> **Validación del grafo**
>
> Tuist valida el grafo al generar el proyecto para asegurar que no haya ciclos y que todas las dependencias sean válidas. Gracias a esto, cualquier equipo puede participar en la evolución del grafo de dependencias sin preocuparse por romperlo.


## Dependencias locales {#local-dependencies}

Los targets pueden depender de otros targets en el mismo proyecto o en proyectos diferentes, así como de binarios. Al instanciar un `Target`, puedes pasar el argumento `dependencies` con cualquiera de las siguientes opciones:

- `Target`: Declara una dependencia con un target dentro del mismo proyecto.
- `Project`: Declara una dependencia con un target en un proyecto diferente.
- `Framework`: Declara una dependencia con un framework binario.
- `Library`: Declara una dependencia con una biblioteca binaria.
- `XCFramework`: Declara una dependencia con un XCFramework binario.
- `SDK`: Declara una dependencia con un SDK del sistema.
- `XCTest`: Declara una dependencia con XCTest.
- `Macro`: Declara una dependencia con un target de macro de Swift definido en el mismo proyecto (consulta [Macros de Swift](#swift-macros)).

> [!NOTE]
> **Condiciones de dependencia**
>
> Cada tipo de dependencia acepta una opción `condition` para enlazar condicionalmente la dependencia según la plataforma. Por defecto, enlaza la dependencia para todas las plataformas que admite el target.


## Dependencias externas {#external-dependencies}

Tuist también te permite declarar dependencias externas en tu proyecto.

### Paquetes de Swift {#swift-packages}

Los Paquetes de Swift son nuestra forma recomendada de declarar dependencias en tu proyecto. Puedes integrarlos usando el mecanismo de integración predeterminado de Xcode o mediante la integración basada en XcodeProj de Tuist.

#### Integración basada en XcodeProj de Tuist {#tuists-xcodeprojbased-integration}

Aunque la integración predeterminada de Xcode es la más cómoda, carece de la flexibilidad y el control necesarios para proyectos medianos y grandes. Para superar esto, Tuist ofrece una integración basada en XcodeProj que te permite integrar Paquetes de Swift en tu proyecto usando targets de XcodeProj. Gracias a ello, no solo te damos más control sobre la integración, sino que también la hacemos compatible con flujos de trabajo como <.localized_link href="/guides/features/cache">el caché</.localized_link> y <.localized_link href="/guides/features/selective-testing">ejecuciones selectivas de tests</.localized_link>.

Es más probable que la integración de XcodeProj tarde más en admitir nuevas funcionalidades de los Paquetes de Swift o en manejar más configuraciones de paquetes. Sin embargo, la lógica de mapeo entre Paquetes de Swift y targets de XcodeProj es de código abierto y la comunidad puede contribuir a ella. Esto contrasta con la integración predeterminada de Xcode, que es de código cerrado y la mantiene Apple.

Para añadir dependencias externas, tendrás que crear un `Package.swift` ya sea bajo `Tuist/` o en la raíz del proyecto.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

> [!TIP]
> **Configuración de paquetes**
>
> La instancia `PackageSettings` envuelta en una directiva del compilador te permite configurar cómo se integran los paquetes. Por ejemplo, en el ejemplo anterior se usa para anular el tipo de producto predeterminado utilizado para los paquetes. Por defecto, no deberías necesitarlo. También puedes usarlo para configurar las firmas esperadas para los targets binarios de SwiftPM mediante `expectedSignatures`.


### Firmas de targets binarios

Si un paquete de Swift local o remoto expone un target de XCFramework binario, puedes configurar su firma esperada usando `PackageSettings.expectedSignatures`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> Si tu proyecto usa configuraciones de compilación personalizadas (configuraciones distintas de las estándar `Debug` y `Release`), debes especificarlas en `PackageSettings` mediante `baseSettings`. Las dependencias externas necesitan conocer las configuraciones de tu proyecto para compilarse correctamente. Por ejemplo:
>
> ```swift
> #if TUIST
>     import ProjectDescription
>
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
>
> Consulta [#8345](https://github.com/tuist/tuist/issues/8345) para más detalles.

El archivo `Package.swift` es solo una interfaz para declarar dependencias externas, nada más. Por eso no defines ningún target ni producto en el paquete. Una vez definidas las dependencias, puedes ejecutar el siguiente comando para resolverlas y descargarlas en el directorio `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Como habrás notado, seguimos un enfoque similar al de [CocoaPods](https://cocoapods.org), donde la resolución de dependencias es un comando independiente. Esto da a los usuarios control sobre cuándo desean resolver y actualizar las dependencias, y permite abrir el proyecto en Xcode con todo listo para compilar. Creemos que la experiencia de desarrollo que ofrece la integración de Apple con el Administrador de Paquetes de Swift se degrada con el tiempo a medida que el proyecto crece.

Desde los targets de tu proyecto puedes referenciar esas dependencias usando el tipo de dependencia `TargetDependency.external`:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **No se generan esquemas para paquetes externos**
>
> Los **esquemas** no se crean automáticamente para proyectos de Paquetes de Swift para mantener limpia la lista de esquemas. Puedes crearlos mediante la interfaz de Xcode.


#### Integración predeterminada de Xcode {#xcodes-default-integration}

Si quieres usar el mecanismo de integración predeterminado de Xcode, puedes pasar la lista `packages` al instanciar un proyecto:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

Y luego referenciarlos desde tus targets:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Al integrar un Macro de Swift o un Plugin de herramienta de compilación desde un Paquete de Swift externo mediante la integración predeterminada de Xcode, decláralo con los tipos `.macro` y `.plugin` respectivamente. Los macros también pueden consumirse mediante [la integración basada en XcodeProj de Tuist](#tuists-xcodeprojbased-integration), y si deseas definir tu propio macro de Swift en lugar de consumir uno desde un paquete, consulta [Macros de Swift](#swift-macros).

> [!WARNING]
> **Plugins de herramientas de compilación de SPM**
>
> Los plugins de herramientas de compilación de SPM deben declararse usando el mecanismo de [integración predeterminada de Xcode](#xcodes-default-integration), incluso cuando uses la [integración basada en XcodeProj de Tuist](#tuists-xcodeprojbased-integration) para las dependencias de tu proyecto.

Los plugins de herramientas de compilación de SPM son programas de Swift que Xcode y SwiftPM ejecutan para descubrir los comandos de compilación concretos que deben ejecutarse para un target. Esos comandos pueden depender del grafo de paquetes, los archivos del target, el directorio de trabajo del plugin, las herramientas del plugin resueltas y las salidas declaradas por el plugin. Algunos plugins también generan archivos que deben formar parte de la misma compilación del target.

La integración basada en XcodeProj de Tuist mapea productos de paquetes a targets nativos de Xcode cuando el mapeo es estático, por ejemplo bibliotecas, binarios, ejecutables y macros. Los plugins de herramientas de compilación no tienen una primitiva nativa equivalente en el proyecto de Xcode fuera de la integración de SwiftPM de Xcode. Aunque un plugin puede eventualmente ejecutar un ejecutable, invocar ese ejecutable desde una fase de compilación de script regular no es equivalente a ejecutar el plugin: Tuist primero necesitaría evaluar el código Swift del plugin, reproducir el contexto del plugin de SwiftPM, descubrir los comandos, modelar las entradas y salidas declaradas y añadir cualquier archivo generado al grafo de targets antes de que Xcode planifique la compilación.

Por esta razón, no se admite declarar un paquete de plugin solo en `Tuist/Package.swift` y consumirlo mediante `.external(name:)`. La alternativa admitida es declarar el paquete en `Project.packages` y añadir el producto del plugin al target consumidor con `.package(product:type: .plugin)`. Esto mantiene el plugin adjunto al proyecto de Xcode generado como una dependencia de producto de Paquete de Swift, para que Xcode y SwiftPM puedan ejecutarlo con el contexto nativo del plugin.

La contrapartida es que Xcode posee esa integración del plugin:

- Xcode resuelve y compila el paquete del plugin a través de su integración con SwiftPM.
- El paquete aparece en el proyecto generado como una referencia de Paquete de Swift en lugar de un target externo generado por Tuist.
- Tuist no puede dar al plugin el mismo nivel de control, validación, caché y comportamiento de tests selectivos que proporciona para productos de paquetes mapeados estáticamente.
- Las compilaciones de CI y locales deben permitir la resolución de paquetes de Xcode para esos paquetes de plugins.

Debido a estas implicaciones, generalmente no recomendamos usar plugins de herramientas de compilación de SPM en proyectos de Tuist. Cuando sea posible, prefiere un script de fase de compilación declarado en el target, o ejecuta la herramienta desde un script fuera del proyecto de Xcode generado antes de invocar Tuist o Xcode.

Una aplicación práctica de un plugin de herramienta de compilación de SPM es realizar linting de código durante la fase de compilación "Run Build Tool Plug-ins" de Xcode. Para generar un proyecto de Xcode con el plugin de herramienta de compilación intacto, declara el paquete en el array `packages` del manifiesto del proyecto y luego incluye un paquete con tipo `.plugin` en las dependencias de un target.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

Dado que [Carthage](https://github.com/carthage/carthage) genera `frameworks` o `xcframeworks`, puedes ejecutar `carthage update` para generar las dependencias en el directorio `Carthage/Build` y luego usar el tipo de dependencia de target `.framework` o `.xcframework` para declarar la dependencia en tu target. Puedes envolver esto en un script que puedes ejecutar antes de generar el proyecto.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **Compilación y pruebas**
>
> Si compilas y pruebas tu proyecto mediante `xcodebuild build` y `tuist test`, igualmente necesitarás asegurarte de que las dependencias resueltas por Carthage estén presentes ejecutando el comando `carthage update` antes de compilar o probar.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) espera un proyecto de Xcode para integrar las dependencias. Puedes usar Tuist para generar el proyecto y luego ejecutar `pod install` para integrar las dependencias creando un espacio de trabajo que contenga tu proyecto y las dependencias de Pods. Puedes envolver esto en un script que puedes ejecutar antes de generar el proyecto.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> Las dependencias de CocoaPods no son compatibles con flujos de trabajo como `build` o `test` que ejecutan `xcodebuild` justo después de generar el proyecto. Tampoco son compatibles con la caché binaria ni con los tests selectivos, ya que la lógica de huellas digitales no tiene en cuenta las dependencias de Pods.


## Macros de Swift {#swift-macros}

Hay dos escenarios distintos al trabajar con [Macros de Swift](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) en un proyecto de Tuist, y vale la pena ser explícito sobre cuál estás utilizando:

- **Consumir un macro definido en un Paquete de Swift externo.** Ambos mecanismos de integración admiten macros. Con [la integración basada en XcodeProj de Tuist](#tuists-xcodeprojbased-integration), declaras el paquete en `Tuist/Package.swift` y dependes de él con `.external(name:)` — Tuist mapea el producto del macro a un target nativo. Con [la integración predeterminada de Xcode](#xcodes-default-integration), declaras la dependencia con `.package(product:type: .macro)`. A diferencia de los plugins de herramientas de compilación, los macros no están restringidos a la integración predeterminada de Xcode.
- **Definir tu propio macro** como parte de tu proyecto, por ejemplo en una biblioteca compartida dentro de tu monorepo. No necesitas un `Package.swift` para esto: Tuist tiene un tipo de producto `.macro` de primera clase, por lo que puedes declarar el target del macro directamente en tus manifiestos.

### Definir tu propio macro {#defining-your-own-macro}

Un macro de Swift es un plugin del compilador: un ejecutable que el compilador de Swift carga y ejecuta en tiempo de compilación. Tuist modela esto de forma nativa con el tipo de producto `.macro`. Aunque Apple no expone un tipo de target de Macro de Swift en los proyectos de Xcode, Tuist lo habilita generando un target de herramienta de línea de comandos, conectándolo como dependencia de los targets que usan el macro e inyectando la bandera `-load-plugin-executable` en sus configuraciones del compilador de Swift. Toda esa infraestructura se gestiona automáticamente.

Un macro típico se divide en dos targets: el target del **plugin** que implementa el macro (`product: .macro`) y el target de la **biblioteca** que declara la interfaz pública del macro (declaraciones `@attached`/`@freestanding`) y depende del plugin mediante `.macro(name:)`. Dado que el plugin se ejecuta en la máquina de compilación, su target es solo para el anfitrión (macOS).

La implementación del macro depende de [swift-syntax](https://github.com/swiftlang/swift-syntax), que declaras como una dependencia externa regular en `Tuist/Package.swift`:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

Luego puedes definir los targets del plugin y la biblioteca del macro directamente en tu proyecto:

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

Cualquier target que enlace `MyLibrary` puede usar ahora el macro; Tuist propaga el plugin para que el compilador pueda cargarlo.


## Estático o dinámico {#static-or-dynamic}

Los frameworks y las bibliotecas pueden enlazarse estática o dinámicamente, **una elección que tiene implicaciones significativas en aspectos como el tamaño de la app y el tiempo de arranque**. A pesar de su importancia, esta decisión a menudo se toma sin mucha consideración.

La **regla general** es que quieres que tantas cosas como sea posible estén enlazadas estáticamente en las compilaciones de release para lograr tiempos de arranque rápidos, y que tantas cosas como sea posible estén enlazadas dinámicamente en las compilaciones de debug para lograr tiempos de iteración rápidos.

El desafío de cambiar entre enlazado estático y dinámico en un grafo de proyecto es que no es trivial en Xcode porque un cambio tiene un efecto en cascada sobre todo el grafo (por ejemplo, las bibliotecas no pueden contener recursos, los frameworks estáticos no necesitan ser embebidos). Apple intentó resolver el problema con soluciones en tiempo de compilación como la decisión automática entre enlazado estático y dinámico de Swift Package Manager, o [Bibliotecas Fusionables](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). Sin embargo, esto añade nuevas variables dinámicas al grafo de compilación, introduciendo nuevas fuentes de no determinismo y provocando potencialmente que algunas funcionalidades como Swift Previews, que dependen del grafo de compilación, se vuelvan poco fiables.

Afortunadamente, Tuist comprime conceptualmente la complejidad asociada al cambio entre estático y dinámico y sintetiza <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">accesores de bundle</.localized_link> que son estándar entre los tipos de enlazado. En combinación con <.localized_link href="/guides/features/projects/dynamic-configuration">configuraciones dinámicas mediante variables de entorno</.localized_link>, puedes pasar el tipo de enlazado en el momento de la invocación y usar el valor en tus manifiestos para establecer el tipo de producto de tus targets.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Ten en cuenta que Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">no prioriza la comodidad mediante configuración implícita debido a sus costes</.localized_link>. Esto significa que dependemos de que establezcas el tipo de enlazado y cualquier configuración de compilación adicional que a veces sea necesaria, como la [bandera de enlazador `-ObjC`](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), para garantizar que los binarios resultantes sean correctos. Por lo tanto, nuestra postura es proporcionarte los recursos, generalmente en forma de documentación, para que tomes las decisiones correctas.

> [!TIP]
> **Ejemplo: The Composable Architecture**
>
> Un Paquete de Swift que muchos proyectos integran es [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). Consulta más detalles en [esta sección](#the-composable-architecture).


### Escenarios {#scenarios}

Hay algunos escenarios donde configurar el enlazado completamente como estático o dinámico no es viable o no es una buena idea. La siguiente es una lista no exhaustiva de escenarios donde podrías necesitar mezclar enlazado estático y dinámico:

- **Apps con extensiones:** Dado que las apps y sus extensiones necesitan compartir código, podrías necesitar hacer esos targets dinámicos. De lo contrario, terminarás con el mismo código duplicado tanto en la app como en la extensión, lo que provoca un aumento del tamaño del binario.
- **Dependencias externas precompiladas:** A veces se te proporcionan binarios precompilados que son estáticos o dinámicos. Los binarios estáticos pueden envolverse en frameworks o bibliotecas dinámicas para enlazarse dinámicamente.

Al realizar cambios en el grafo, Tuist lo analizará y mostrará una advertencia si detecta un "efecto secundario estático". Esta advertencia tiene como objetivo ayudarte a identificar problemas que podrían surgir al enlazar un target estáticamente que depende transitivamente de un target estático a través de targets dinámicos. Estos efectos secundarios a menudo se manifiestan como un aumento del tamaño del binario o, en los peores casos, fallos en tiempo de ejecución.

## Solución de problemas {#troubleshooting}

### Dependencias de Objective-C {#objectivec-dependencies}

Al integrar dependencias de Objective-C, puede ser necesario incluir ciertas banderas en el target consumidor para evitar fallos en tiempo de ejecución, como se detalla en [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Dado que el sistema de compilación y Tuist no tienen forma de inferir si la bandera es necesaria o no, y dado que la bandera conlleva efectos secundarios potencialmente indeseables, Tuist no aplicará automáticamente ninguna de estas banderas. Además, como Swift Package Manager considera que `-ObjC` se incluye mediante un `.unsafeFlag`, la mayoría de los paquetes no pueden incluirla como parte de sus configuraciones de enlazado predeterminadas cuando sea necesario.

Los consumidores de dependencias de Objective-C (o targets internos de Objective-C) deben aplicar las banderas `-ObjC` o `-force_load` cuando sea necesario estableciendo `OTHER_LDFLAGS` en los targets consumidores.

### Firebase y otras bibliotecas de Google {#firebase-other-google-libraries}

Las bibliotecas de código abierto de Google, aunque potentes, pueden ser difíciles de integrar en Tuist, ya que a menudo utilizan arquitecturas y técnicas no estándar en su construcción.

Aquí tienes algunos consejos que podría ser necesario seguir para integrar Firebase y otras bibliotecas de Google para plataformas Apple:

#### Asegúrate de que `-ObjC` se añada a `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Muchas de las bibliotecas de Google están escritas en Objective-C. Por ello, cualquier target consumidor deberá incluir la etiqueta `-ObjC` en su configuración de compilación `OTHER_LDFLAGS`. Esto puede configurarse en un archivo `.xcconfig` o especificarse manualmente en la configuración del target dentro de tus manifiestos de Tuist. Un ejemplo:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Consulta la sección [Dependencias de Objective-C](#objective-c-dependencies) anterior para más detalles.

#### Establece el tipo de producto para `FBLPromises` como framework dinámico {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Ciertas bibliotecas de Google dependen de `FBLPromises`, otra de las bibliotecas de Google. Podrías encontrarte con un fallo que mencione a `FBLPromises`, similar a este:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Establecer explícitamente el tipo de producto de `FBLPromises` a `.framework` en tu archivo `Package.swift` debería solucionar el problema:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### The Composable Architecture {#the-composable-architecture}

Como se describe [aquí](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) y en la [sección de solución de problemas](#troubleshooting), deberás establecer la configuración de compilación `OTHER_LDFLAGS` a `$(inherited) -ObjC` al enlazar los paquetes estáticamente, que es el tipo de enlazado predeterminado de Tuist. Alternativamente, puedes anular el tipo de producto del paquete para que sea dinámico. Al enlazar estáticamente, los targets de pruebas y de aplicación suelen funcionar sin problemas, pero las previsualizaciones de SwiftUI no funcionan. Esto puede resolverse enlazando todo dinámicamente. En el siguiente ejemplo también se añade [Sharing](https://github.com/pointfreeco/swift-sharing) como dependencia, ya que a menudo se usa junto con The Composable Architecture y tiene sus propios [problemas de configuración](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

La siguiente configuración enlazará todo dinámicamente, por lo que los targets de aplicación + pruebas y las previsualizaciones de SwiftUI funcionarán.

> [!TIP]
> **Estático o dinámico**
>
> El enlazado dinámico no siempre es recomendable. Consulta la sección [Estático o dinámico](#static-or-dynamic) para más detalles. En este ejemplo, todas las dependencias se enlazan dinámicamente sin condiciones por simplicidad.


```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

> [!WARNING]
> En lugar de `import Sharing`, tendrás que usar `import SwiftSharing`.


### Dependencias estáticas transitivas filtrándose a través de `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Cuando un framework o biblioteca dinámica depende de otros estáticos mediante `import StaticSwiftModule`, los símbolos se incluyen en el `.swiftmodule` del framework o biblioteca dinámica, lo que potencialmente <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">puede hacer que la compilación falle</.localized_link>. Para evitarlo, tendrás que importar la dependencia estática usando <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>:

```swift
internal import StaticModule
```

> [!NOTE]
> El nivel de acceso en las importaciones se incluyó en Swift 6. Si estás usando versiones anteriores de Swift, necesitas usar <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link> en su lugar:


```swift
@_implementationOnly import StaticModule
```
