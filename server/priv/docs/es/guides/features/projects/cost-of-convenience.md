---
{
  "title": "El coste de la comodidad",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Cómo los comportamientos implícitos de Xcode causan problemas y cómo Tuist los previene."
}
---
# El coste de la comodidad {#the-cost-of-convenience}

Diseñar un editor de código que el espectro **desde proyectos pequeños hasta a gran escala pueda usar** es una tarea desafiante. Muchas herramientas abordan el problema mediante capas en su solución y ofreciendo extensibilidad. La capa más baja es muy de bajo nivel y está cerca del sistema de compilación subyacente, mientras que la capa superior es una abstracción de alto nivel que resulta cómoda de usar pero menos flexible. De este modo, hacen que las cosas simples sean fáciles y todo lo demás sea posible.

Sin embargo, **[Apple](https://www.apple.com) decidió adoptar un enfoque diferente con Xcode**. Se desconoce la razón, pero es probable que optimizar para los desafíos de los proyectos a gran escala nunca haya sido su objetivo. Sobreinvirtieron en comodidad para proyectos pequeños, ofrecieron poca flexibilidad y acoplaron fuertemente las herramientas con el sistema de compilación subyacente. Para lograr esa comodidad, proporcionan valores predeterminados sensatos, que puedes reemplazar fácilmente, y añadieron muchos comportamientos implícitos resueltos en tiempo de compilación que son la causa de numerosos problemas a escala.

## Explicitud y escala {#explicitness-and-scale}

Cuando trabajas a escala, **la explicitud es clave**. Permite que el sistema de compilación analice y comprenda la estructura del proyecto y sus dependencias con antelación, y realice optimizaciones que de otro modo serían imposibles. Esa misma explicitud también es clave para garantizar que funcionalidades del editor como las [vistas previas de SwiftUI](https://developer.apple.com/documentation/swiftui/previews-in-xcode) o las [macros de Swift](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) funcionen de forma fiable y predecible. Dado que Xcode y los proyectos de Xcode adoptaron la implicitud como una elección de diseño válida para lograr comodidad, un principio que el Administrador de Paquetes de Swift ha heredado, las dificultades de usar Xcode también están presentes en el Administrador de Paquetes de Swift.

> [!NOTE]
> **El papel de Tuist**
>
> Podríamos resumir el papel de Tuist como una herramienta que evita proyectos definidos de forma implícita y aprovecha la explicitud para ofrecer una mejor experiencia de desarrollo (por ejemplo, validaciones, optimizaciones). Herramientas como [Bazel](https://bazel.build) van más allá al llevarlo al nivel del sistema de compilación.


Este es un tema apenas debatido en la comunidad, pero es significativo. Mientras trabajábamos en Tuist, observamos que muchas organizaciones y desarrolladores pensaban que los desafíos actuales que enfrentan se resolverían con el [Administrador de Paquetes de Swift](https://www.swift.org/documentation/package-manager/), pero no se dan cuenta de que, al construir sobre los mismos principios, aunque mitiga los tan conocidos conflictos de Git, degrada la experiencia de desarrollo en otras áreas y sigue haciendo que los proyectos no sean optimizables.

En las siguientes secciones, analizaremos ejemplos reales de cómo la implicitud afecta la experiencia de desarrollo y la salud del proyecto. La lista no es exhaustiva, pero debería darte una buena idea de los desafíos que podrías enfrentar al trabajar con proyectos de Xcode o paquetes de Swift.

## La comodidad interponiéndose en tu camino {#convenience-getting-in-your-way}

### Directorio compartido de productos compilados {#shared-built-products-directory}

Xcode utiliza un directorio dentro del directorio de datos derivados para cada producto. En él almacena los artefactos de compilación, como los binarios compilados, los archivos dSYM y los registros. Como todos los productos de un proyecto van al mismo directorio, que por defecto es visible desde otros destinos para enlazar contra ellos, **puedes terminar con destinos que dependen implícitamente entre sí.** Aunque esto podría no ser un problema cuando tienes solo unos pocos destinos, puede manifestarse como compilaciones fallidas difíciles de depurar a medida que el proyecto crece.

La consecuencia de esta decisión de diseño es que muchos proyectos se compilan accidentalmente con un grafo que no está bien definido.

> [!TIP]
> **Detección de dependencias implícitas de Tuist**
>
> Tuist proporciona un <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">comando</.localized_link> para detectar dependencias implícitas. Puedes usar el comando para validar en CI que todas tus dependencias sean explícitas.


### Buscar dependencias implícitas en esquemas {#find-implicit-dependencies-in-schemes}

Definir y mantener un grafo de dependencias en Xcode se vuelve más difícil a medida que el proyecto crece. Es difícil porque están codificados en los archivos `.pbxproj` como fases de compilación y ajustes de compilación, no hay herramientas para visualizar y trabajar con el grafo, y los cambios en el grafo (por ejemplo, añadir un nuevo framework dinámico precompilado) pueden requerir cambios de configuración aguas arriba (por ejemplo, añadir una nueva fase de compilación para copiar el framework en el bundle).

Apple decidió en algún momento que, en lugar de evolucionar el modelo de grafo hacia algo más manejable, tendría más sentido añadir una opción para resolver dependencias implícitas en tiempo de compilación. Esta es nuevamente una elección de diseño cuestionable porque puedes terminar con tiempos de compilación más lentos o compilaciones impredecibles. Por ejemplo, una compilación podría pasar localmente debido a algún estado en los datos derivados, que actúa como un [singleton](https://en.wikipedia.org/wiki/Singleton_pattern), pero luego fallar al compilar en CI porque el estado es diferente.

> [!TIP]
> Recomendamos desactivar esto en los esquemas de tu proyecto y usar herramientas como Tuist que facilitan la gestión del grafo de dependencias.


### Vistas previas de SwiftUI y bibliotecas/frameworks estáticos {#swiftui-previews-and-static-librariesframeworks}

Algunas funcionalidades del editor, como las vistas previas de SwiftUI o las macros de Swift, requieren la compilación del grafo de dependencias desde el archivo que se está editando. Esta integración entre el editor requiere que el sistema de compilación resuelva cualquier implicitud y genere los artefactos correctos necesarios para que esas funcionalidades funcionen. Como puedes imaginar, **cuanto más implícito sea el grafo, más desafiante será la tarea para el sistema de compilación**, por lo que no sorprende que muchas de estas funcionalidades no funcionen de forma fiable. A menudo escuchamos a desarrolladores decir que dejaron de usar las vistas previas de SwiftUI hace tiempo porque eran demasiado inestables. En su lugar, usan aplicaciones de ejemplo o evitan ciertas cosas, como el uso de bibliotecas estáticas o fases de compilación de scripts, porque hacen que la funcionalidad falle.

### Bibliotecas combinables {#mergeable-libraries}

Los frameworks dinámicos, aunque son más flexibles y fáciles de usar, tienen un impacto negativo en el tiempo de lanzamiento de las aplicaciones. Por otro lado, las bibliotecas estáticas se lanzan más rápido, pero afectan al tiempo de compilación y son un poco más difíciles de manejar, especialmente en escenarios de grafos complejos. *¿No sería genial poder cambiar entre uno u otro según la configuración?* Eso es lo que Apple debió pensar cuando decidió trabajar en las bibliotecas combinables. Pero una vez más, trasladaron más inferencia al tiempo de compilación. Si ya es complejo razonar sobre un grafo de dependencias, imagina tener que hacerlo cuando la naturaleza estática o dinámica del destino se resuelva en tiempo de compilación basándose en algunas configuraciones de compilación en ciertos destinos. Buena suerte haciendo que eso funcione de forma fiable mientras garantizas que funcionalidades como las vistas previas de SwiftUI no fallen.

**Muchos usuarios acuden a Tuist queriendo usar bibliotecas combinables y nuestra respuesta es siempre la misma. No lo necesitas.** Puedes controlar la naturaleza estática o dinámica de tus destinos en el momento de la generación, lo que da lugar a un proyecto cuyo grafo se conoce antes de la compilación. No hace falta resolver ninguna variable en tiempo de compilación.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Explícito, explícito y explícito {#explicit-explicit-and-explicit}

Si hay un principio importante no escrito que recomendamos a todo desarrollador u organización que quiera escalar su desarrollo con Xcode, es que deben abrazar la explicitud. Y si la explicitud es difícil de gestionar con proyectos Xcode crudos, deberían considerar otra opción, ya sea [Tuist](https://tuist.io) o [Bazel](https://bazel.build). **Solo entonces serán posibles la fiabilidad, la predictibilidad y las optimizaciones.**

## Futuro {#future}

Se desconoce si Apple hará algo para prevenir todos los problemas anteriores. Sus continuas decisiones integradas en Xcode y en Swift Package Manager no sugieren que vayan a hacerlo. Una vez que permites la configuración implícita como un estado válido, **es difícil avanzar desde ahí sin introducir cambios incompatibles.** Volver a los principios fundamentales y repensar el diseño de las herramientas podría llevar a romper muchos proyectos Xcode que han compilado accidentalmente durante años. Imagina el revuelo de la comunidad si eso ocurriera.

Apple se encuentra en un problema del huevo y la gallina. La comodidad es lo que ayuda a los desarrolladores a empezar rápidamente y crear más aplicaciones para su ecosistema. Pero sus decisiones para hacer que la experiencia sea cómoda a esa escala están dificultando que garanticen que algunas funcionalidades de Xcode funcionen de forma fiable.

Dado que el futuro es incierto, intentamos **acercarnos lo máximo posible a los estándares de la industria y a los proyectos Xcode**. Prevenimos los problemas anteriores y aprovechamos el conocimiento que tenemos para ofrecer una mejor experiencia de desarrollo. Idealmente, no tendríamos que recurrir a la generación de proyectos para ello, pero la falta de extensibilidad de Xcode y de Swift Package Manager la convierten en la única opción viable. Además, es una opción segura porque tendrán que romper los proyectos Xcode para romper los proyectos Tuist.

Idealmente, **el sistema de compilación sería más extensible**, pero ¿no sería mala idea tener plugins o extensiones que interactúen con un mundo de implicitud? No parece una buena idea. Así que parece que necesitaremos herramientas externas como Tuist o [Bazel](https://bazel.build) para ofrecer una mejor experiencia de desarrollo. O quizás Apple nos sorprenda a todos y haga Xcode más extensible y explícito...

Hasta que eso ocurra, tienes que elegir si quieres abrazar la comodidad de Xcode y asumir la deuda técnica que conlleva, o confiar en nosotros en este viaje para ofrecerte una mejor experiencia de desarrollo. No te defraudaremos.
