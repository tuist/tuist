---
{
  "title": "Principios",
  "titleTemplate": ":title · Colaboradores · Tuist",
  "description": "Este documento describe los principios que guían el desarrollo de Tuist."
}
---
# Principios {#principles}

Esta página describe los principios que son pilares del diseño y desarrollo de Tuist. Evolucionan con el proyecto y tienen como objetivo garantizar un crecimiento sostenible bien alineado con los fundamentos del proyecto.

## Priorizar las convenciones {#default-to-conventions}

Una de las razones por las que existe Tuist es que Xcode carece de convenciones sólidas, lo que da lugar a proyectos complejos difíciles de escalar y mantener. Por eso, Tuist adopta un enfoque diferente al priorizar convenciones simples y bien diseñadas. **Los desarrolladores pueden optar por no seguir las convenciones, pero es una decisión consciente que no resulta natural.**

Por ejemplo, existe una convención para definir dependencias entre targets utilizando la interfaz pública proporcionada. Al hacerlo, Tuist garantiza que los proyectos se generen con las configuraciones correctas para que el enlace funcione. Los desarrolladores tienen la opción de definir las dependencias mediante ajustes de compilación, pero lo harían de forma implícita y, por tanto, romperían funcionalidades de Tuist como `tuist graph` o `tuist cache` que dependen de que se sigan ciertas convenciones.

La razón por la que priorizamos las convenciones es que cuantas más decisiones podamos tomar en nombre de los desarrolladores, más podrán centrarse en crear funcionalidades para sus aplicaciones. Cuando no hay convenciones, como ocurre en muchos proyectos, tenemos que tomar decisiones que acaban siendo inconsistentes con otras y, como consecuencia, surge una complejidad accidental difícil de gestionar.

## Los manifiestos son la fuente de verdad {#manifests-are-the-source-of-truth}

Tener muchas capas de configuraciones y contratos entre ellas da lugar a una configuración de proyecto difícil de comprender y mantener. Piensa por un momento en un proyecto promedio. La definición del proyecto reside en los directorios `.xcodeproj`, la CLI en scripts (por ejemplo, `Fastfiles`) y la lógica de CI en pipelines. Son tres capas con contratos entre ellas que debemos mantener. *¿Con qué frecuencia te has encontrado en una situación en la que cambiaste algo en tus proyectos y, una semana después, te diste cuenta de que los scripts de lanzamiento se rompieron?*

Podemos simplificar esto teniendo una única fuente de verdad: los archivos de manifiesto. Estos archivos proporcionan a Tuist la información que necesita para generar proyectos de Xcode que los desarrolladores puedan usar para editar sus archivos. Además, permite disponer de comandos estándar para compilar proyectos desde un entorno local o de CI.

**Tuist debe asumir la complejidad y exponer una interfaz simple, segura y agradable para describir los proyectos de la manera más explícita posible.**

## Hacer explícito lo implícito {#make-the-implicit-explicit}

Xcode admite configuraciones implícitas. Un buen ejemplo es la inferencia de dependencias definidas implícitamente. Aunque lo implícito funciona bien en proyectos pequeños, donde las configuraciones son simples, a medida que los proyectos crecen puede causar lentitud o comportamientos extraños.

Tuist debe proporcionar APIs explícitas para los comportamientos implícitos de Xcode. También debe admitir la definición de la implicitud de Xcode, pero implementada de tal manera que anime a los desarrolladores a optar por el enfoque explícito. Admitir la implicitud y las complejidades de Xcode facilita la adopción de Tuist, tras lo cual los equipos pueden dedicar tiempo a eliminar la implicitud.

La definición de dependencias es un buen ejemplo de ello. Aunque los desarrolladores pueden definir dependencias mediante ajustes de compilación y fases, Tuist proporciona una API elegante que fomenta su adopción.

**Diseñar la API para que sea explícita permite a Tuist ejecutar comprobaciones y optimizaciones en los proyectos que de otro modo no serían posibles.** Además, habilita funcionalidades como `tuist graph`, que exporta una representación del grafo de dependencias, o `tuist cache`, que almacena en caché todos los targets como binarios.

> [!TIP]
> Debemos tratar cada solicitud para portar funcionalidades desde Xcode como una oportunidad para simplificar conceptos con APIs simples y explícitas.


## Mantén la simplicidad {#keep-it-simple}

Uno de los principales desafíos al escalar proyectos de Xcode proviene del hecho de que **Xcode expone mucha complejidad a los usuarios.** Debido a ello, los equipos tienen un alto factor de dependencia y solo unas pocas personas entienden el proyecto y los errores que arroja el sistema de compilación. Es una mala situación porque el equipo depende de pocas personas.

Xcode es una gran herramienta, pero tantos años de mejoras, nuevas plataformas y lenguajes de programación se reflejan en su superficie, que ha luchado por mantenerse simple.

Tuist debe aprovechar la oportunidad para mantener las cosas simples, porque trabajar en cosas simples es divertido y nos motiva. Nadie quiere pasar tiempo intentando depurar un error que ocurre al final del proceso de compilación o entendiendo por qué no pueden ejecutar la aplicación en sus dispositivos. Xcode delega las tareas en su sistema de compilación subyacente y, en algunos casos, hace un muy mal trabajo traduciendo los errores en acciones concretas. ¿Alguna vez has recibido un error *“framework X not found”* y no sabías qué hacer? Imagina si obtuviéramos una lista de posibles causas raíz del error.

## Partir de la experiencia del desarrollador {#start-from-the-developers-experience}

Parte de la razón por la que hay falta de innovación alrededor de Xcode, o dicho de otra manera, no tanta como en otros entornos de programación, es porque **a menudo empezamos analizando problemas desde soluciones existentes.** Como consecuencia, la mayoría de las soluciones que encontramos hoy giran en torno a las mismas ideas y flujos de trabajo. Aunque es bueno incluir soluciones existentes en las ecuaciones, no debemos dejar que restrinjan nuestra creatividad.

Nos gusta pensar, como dice [Tom Preston](https://tom.preston-werner.com/) en [este podcast](https://tom.preston-werner.com/): *“La mayoría de las cosas se pueden lograr; lo que tengas en la cabeza probablemente puedas hacerlo con código, siempre que sea posible dentro de las limitaciones del universo”.* Si **imaginamos cómo nos gustaría que fuera la experiencia del desarrollador**, es solo cuestión de tiempo lograrlo: empezar a analizar los problemas desde la experiencia del desarrollador nos da un punto de vista único que nos llevará a soluciones que a los usuarios les encantará usar.

Podemos sentirnos tentados a seguir lo que hace todo el mundo, incluso si eso significa aceptar las incomodidades de las que todos siguen quejándose. No hagamos eso. ¿Cómo imagino archivar mi aplicación? ¿Cómo me gustaría que fuera la firma de código? ¿Qué procesos puedo ayudar a simplificar con Tuist? Por ejemplo, añadir soporte para [Fastlane](https://fastlane.tools/) es una solución a un problema que primero debemos entender. Podemos llegar a la raíz del problema haciendo preguntas de “por qué”. Una vez que acotamos de dónde viene la motivación, podemos pensar en cómo Tuist puede ayudar mejor. Quizá la solución sea integrarse con Fastlane, pero es importante no descartar otras soluciones igualmente válidas que podamos poner sobre la mesa antes de tomar decisiones.

## Los errores pueden y ocurrirán {#errors-can-and-will-happen}

Nosotros, los desarrolladores, tenemos la tentación inherente de ignorar que pueden ocurrir errores. Como resultado, diseñamos y probamos software considerando solo el escenario ideal.

Swift, su sistema de tipos y un código bien estructurado pueden ayudar a prevenir algunos errores, pero no todos, porque algunos están fuera de nuestro control. No podemos asumir que el usuario siempre tendrá conexión a internet o que los comandos del sistema se ejecutarán correctamente. Los entornos en los que se ejecuta Tuist no son entornos aislados que controlemos, por lo que debemos esforzarnos por comprender cómo pueden cambiar y afectar a Tuist.

Los errores mal gestionados generan una mala experiencia de usuario y los usuarios pueden perder la confianza en el proyecto. Queremos que los usuarios disfruten de cada aspecto de Tuist, incluso de cómo les presentamos los errores.

Debemos ponernos en el lugar de los usuarios e imaginar qué esperaríamos que nos dijera el error. Si el lenguaje de programación es el canal de comunicación por el que se propagan los errores y los usuarios son el destino de esos errores, deben redactarse en el mismo idioma que habla el destinatario (los usuarios). Deben incluir suficiente información para saber qué ocurrió y ocultar la información que no es relevante. Además, deben ser accionables, indicando a los usuarios qué pasos pueden seguir para recuperarse de ellos.

Y, por último pero no menos importante, nuestros casos de prueba deben contemplar escenarios de fallo. No solo garantizan que estamos gestionando los errores como debemos, sino que también evitan que futuros desarrolladores rompan esa lógica.
