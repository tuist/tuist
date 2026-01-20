---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# El coste de la comodidad {#the-cost-of-convenience}

Diseñar un editor de código que el espectro **de proyectos de pequeña a gran
escala pueda utilizar** es una tarea difícil. Muchas herramientas abordan el
problema estratificando su solución y proporcionando extensibilidad. La capa
inferior es de muy bajo nivel y cercana al sistema de compilación subyacente, y
la capa superior es una abstracción de alto nivel que es cómoda de usar pero
menos flexible. De este modo, facilitan las cosas sencillas y hacen posible todo
lo demás.

Sin embargo, **[Apple](https://www.apple.com) decidió adoptar un enfoque
diferente con Xcode**. La razón es desconocida, pero es probable que la
optimización para los retos de los proyectos a gran escala nunca haya sido su
objetivo. Invirtieron demasiado en la comodidad para los proyectos pequeños,
proporcionaron poca flexibilidad y acoplaron fuertemente las herramientas con el
sistema de compilación subyacente. Para lograr la comodidad, proporcionan
valores predeterminados sensibles, que se pueden reemplazar fácilmente, y
añadieron un montón de comportamientos implícitos resueltos en tiempo de
compilación que son los culpables de muchos problemas a escala.

## Explicitud y escala {#explicitness-and-scale}

Cuando se trabaja a escala, la explicitud de **es clave**. Permite al sistema de
compilación analizar y comprender la estructura y las dependencias del proyecto
con antelación, y realizar optimizaciones que serían imposibles de otro modo. La
misma explicitud es también clave para asegurar que las características del
editor como [SwiftUI
previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) o
[Swift
Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)
funcionen de forma fiable y predecible. Debido a que Xcode y los proyectos Xcode
adoptaron la implicitud como una opción de diseño válida para lograr la
comodidad, un principio que el Gestor de paquetes Swift ha heredado, las
dificultades de uso de Xcode también están presentes en el Gestor de paquetes
Swift.

::: info EL PAPEL DEL TUISTA
<!-- -->
Podríamos resumir el papel de Tuist como una herramienta que evita los proyectos
definidos implícitamente y aprovecha la explicitud para ofrecer una mejor
experiencia al desarrollador (por ejemplo, validaciones, optimizaciones).
Herramientas como [Bazel](https://bazel.build) van más allá y lo llevan al nivel
del sistema de compilación.
<!-- -->
:::

Este es un tema del que apenas se habla en la comunidad, pero es importante.
Mientras trabajábamos en Tuist, nos hemos dado cuenta de que muchas
organizaciones y desarrolladores piensan que los retos actuales a los que se
enfrentan se solucionarán con [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), pero de lo que
no se dan cuenta es de que, como se basa en los mismos principios, aunque mitiga
los tan conocidos conflictos de Git, degradan la experiencia del desarrollador
en otras áreas y siguen haciendo que los proyectos no sean optimizables.

En las siguientes secciones, discutiremos algunos ejemplos reales de cómo la
implicitud afecta a la experiencia del desarrollador y a la salud del proyecto.
La lista no es exhaustiva, pero debería darte una buena idea de los retos a los
que podrías enfrentarte cuando trabajes con proyectos Xcode o paquetes Swift.

## La comodidad se interpone en tu camino {#convenience-getting-in-your-way}

### Directorio de productos construidos compartidos {#directorio-de-productos-construidos-compartidos}

Xcode utiliza un directorio dentro del directorio de datos derivados para cada
producto. Dentro de él, almacena los artefactos de construcción, tales como los
binarios compilados, los archivos dSYM, y los registros. Debido a que todos los
productos de un proyecto van en el mismo directorio, que es visible por defecto
de otros objetivos para vincular contra, **usted podría terminar con objetivos
que implícitamente dependen unos de otros.** Si bien esto puede no ser un
problema cuando se tienen sólo unos pocos objetivos, puede manifestarse como
errores de compilación que son difíciles de depurar cuando el proyecto crece.

La consecuencia de esta decisión de diseño es que muchos proyectos compilan
accidentalmente con un gráfico que no está bien definido.

::: tip DETECCIÓN TUISTA DE DEPENDENCIAS IMPLÍCITAS
<!-- -->
Tuist proporciona un
<LocalizedLink href="/guides/features/inspect/implicit-dependencies">comando</LocalizedLink>
para detectar dependencias implícitas. Puedes utilizar el comando para validar
en CI que todas tus dependencias son explícitas.
<!-- -->
:::

### Encontrar dependencias implícitas en esquemas {#find-implicit-dependencies-in-schemes}

Definir y mantener un gráfico de dependencias en Xcode se hace más difícil a
medida que el proyecto crece. Es difícil porque están codificados en los
archivos `.pbxproj` como fases de compilación y ajustes de compilación, no hay
herramientas para visualizar y trabajar con el gráfico, y los cambios en el
gráfico (por ejemplo, añadir un nuevo marco dinámico precompilado), podrían
requerir cambios de configuración aguas arriba (por ejemplo, añadir una nueva
fase de compilación para copiar el marco en el paquete).

Apple decidió en algún momento que en lugar de evolucionar el modelo de grafos
hacia algo más manejable, tendría más sentido añadir una opción para resolver
las dependencias implícitas en tiempo de compilación. Esto es, una vez más, una
elección de diseño cuestionable, ya que podría terminar con tiempos de
compilación más lentos o compilaciones impredecibles. Por ejemplo, una
compilación podría pasar localmente debido a algún estado en los datos
derivados, que actúa como un
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern), pero luego fallar
al compilar en CI porque el estado es diferente.

::: consejo
<!-- -->
Recomendamos deshabilitar esto en los esquemas de tu proyecto, y usar como Tuist
que facilita la gestión del grafo de dependencias.
<!-- -->
:::

### SwiftUI Previews and static libraries/frameworks {#swiftui-previews-and-static-librariesframeworks}

Algunas funciones del editor como SwiftUI Previews o Swift Macros requieren la
compilación del gráfico de dependencias del archivo que se está editando. Esta
integración entre el editor requiere que el sistema de compilación resuelva
cualquier implícito y la salida de los artefactos correctos que son necesarios
para que esas características funcionen. Como se puede imaginar, **cuanto más
implícito es el gráfico, más difícil es la tarea para el sistema de
compilación**, y por lo tanto no es de extrañar que muchas de estas
características no funcionen de forma fiable. A menudo escuchamos de los
desarrolladores que dejaron de usar las vistas previas de SwiftUI hace mucho
tiempo porque eran demasiado poco fiables. En su lugar, utilizan aplicaciones de
ejemplo, o evitan ciertas cosas, como el uso de bibliotecas estáticas o fases de
compilación de secuencias de comandos, porque hacen que la función se rompa.

### Bibliotecas fusionables {#mergeable-libraries}

Los frameworks dinámicos, aunque son más flexibles y fáciles de trabajar, tienen
un impacto negativo en el tiempo de lanzamiento de las aplicaciones. Por otro
lado, las librerías estáticas son más rápidas de lanzar, pero tienen un impacto
en el tiempo de compilación y son un poco más difíciles de trabajar,
especialmente en escenarios gráficos complejos. *¿No sería genial poder cambiar
entre una u otra dependiendo de la configuración?* Eso es lo que debió pensar
Apple cuando decidió trabajar en librerías fusionables. Pero una vez más,
trasladaron más inferencia en tiempo de compilación al tiempo de compilación. Si
razonar sobre un gráfico de dependencia, imaginar tener que hacerlo cuando la
naturaleza estática o dinámica del objetivo se resolverá en tiempo de
compilación sobre la base de algunos ajustes de compilación en algunos
objetivos. Buena suerte haciendo que funcione de forma fiable al tiempo que
garantiza características como las vistas previas SwiftUI no se rompen.

**Muchos usuarios vienen a Tuist queriendo utilizar bibliotecas fusionables y
nuestra respuesta es siempre la misma. No es necesario.** Puedes controlar la
naturaleza estática o dinámica de tus objetivos en tiempo de generación, dando
lugar a un proyecto cuyo gráfico se conoce antes de la compilación. No es
necesario resolver variables en tiempo de compilación.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Explícito, explícito y explícito {#explícito-explícito-y-explícito}

Si hay un principio importante no escrito que recomendamos a cada desarrollador
u organización que quiere que su desarrollo con Xcode escale, es que deben
adoptar la explicitud. Y si la explicitud es difícil de manejar con proyectos
Xcode en bruto, deberían considerar algo más, ya sea [Tuist](https://tuist.io) o
[Bazel](https://bazel.build). **Sólo entonces la fiabilidad, la previsibilidad y
las optimizaciones serán posibles.**

## Futuro {#future}

Se desconoce si Apple hará algo para evitar todos los problemas anteriores. Sus
continuas decisiones integradas en Xcode y el gestor de paquetes Swift no
sugieren que lo vayan a hacer. Una vez que se permite la configuración implícita
como un estado válido, **es difícil pasar de ahí sin introducir cambios de
ruptura.** Volver a los primeros principios y repensar el diseño de las
herramientas podría llevar a romper muchos proyectos de Xcode que se compilaron
accidentalmente durante años. Imagina el alboroto de la comunidad si eso
sucediera.

Apple se encuentra en una especie de problema del huevo y la gallina. La
comodidad es lo que ayuda a los desarrolladores a empezar rápidamente y crear
más aplicaciones para su ecosistema. Pero su decisión de hacer que la
experiencia sea cómoda a esa escala les está dificultando garantizar que algunas
de las funciones de Xcode funcionen de forma fiable.

Dado que el futuro es desconocido, intentamos **estar lo más cerca posible de
los estándares de la industria y de los proyectos de Xcode**. Evitamos los
problemas anteriores y aprovechamos los conocimientos que tenemos para ofrecer
una mejor experiencia al desarrollador. Lo ideal sería no tener que recurrir a
la generación de proyectos para ello, pero la falta de extensibilidad de Xcode y
el gestor de paquetes Swift hacen que sea la única opción viable. Y también es
una opción segura porque tendrán que romper los proyectos de Xcode para romper
los proyectos de Tuist.

Idealmente, **el sistema de construcción fuera más extensible**, pero ¿no sería
una mala idea tener plugins/extensiones que contratan con un mundo de
implícitos? No parece una buena idea. Así que parece que necesitaremos
herramientas externas como Tuist o [Bazel](https://bazel.build) para
proporcionar una mejor experiencia al desarrollador. O quizás Apple nos
sorprenda a todos y haga Xcode más extensible y explícito...

Hasta que eso ocurra, tienes que elegir si quieres abrazar la convenciencia de
Xcode y asumir la deuda que conlleva, o confiar en nosotros en este viaje para
ofrecer una mejor experiencia al desarrollador. No te decepcionaremos.
