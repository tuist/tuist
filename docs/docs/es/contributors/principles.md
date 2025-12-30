---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Principios {#principles}

En esta página se describen los principios que constituyen los pilares del
diseño y el desarrollo de Tuist. Evolucionan con el proyecto y pretenden
garantizar un crecimiento sostenible que esté bien alineado con los cimientos
del proyecto.

## Convenciones por defecto {#default-to-conventions}

Una de las razones por las que Tuist existe es porque Xcode es débil en
convenciones y eso lleva a proyectos complejos que son difíciles de escalar y
mantener. Por esa razón, Tuist adopta un enfoque diferente por defecto a las
convenciones simples y bien diseñados. **Los desarrolladores pueden optar por
las convenciones, pero eso es una decisión consciente que no se siente
natural.**

Por ejemplo, existe una convención para definir dependencias entre objetivos
utilizando la interfaz pública proporcionada. Al hacer esto, Tuist se asegura de
que los proyectos se generan con las configuraciones correctas para que la
vinculación funcione. Los desarrolladores tienen la opción de definir las
dependencias a través de la configuración de compilación, pero lo estarían
haciendo implícitamente y por lo tanto rompiendo características de Tuist como
`tuist graph` o `tuist cache` que dependen de que se sigan algunas convenciones.

La razón por la que recurrimos a las convenciones es que cuantas más decisiones
podamos tomar en nombre de los desarrolladores, más centrados estarán en crear
características para sus aplicaciones. Cuando nos quedamos sin convenciones,
como ocurre en muchos proyectos, tenemos que tomar decisiones que terminarán por
no ser coherentes con otras decisiones y, como consecuencia, habrá una
complejidad accidental que será difícil de gestionar.

## Los manifiestos son la fuente de la verdad {#manifests-are-the-source-of-truth}

Tener muchas capas de configuraciones y contratos entre ellas da como resultado
una configuración del proyecto difícil de razonar y mantener. Piensa por un
segundo en un proyecto medio. La definición del proyecto vive en los directorios
`.xcodeproj`, la CLI en scripts (por ejemplo `Fastfiles`), y la lógica CI en
pipelines. Son tres capas con contratos entre ellas que tenemos que mantener.
*¿Cuántas veces te has encontrado en una situación en la que has cambiado algo
en tus proyectos, y luego una semana más tarde te diste cuenta de que los
scripts de lanzamiento se rompieron?*

Podemos simplificar esto teniendo una única fuente de verdad, los archivos de
manifiesto. Esos archivos proporcionan a Tuist la información que necesita para
generar proyectos Xcode que los desarrolladores pueden utilizar para editar sus
archivos. Además, permite disponer de comandos estándar para construir proyectos
desde un entorno local o CI.

**Tuist debe asumir la complejidad y exponer una interfaz sencilla, segura y
agradable para describir sus proyectos de la forma más explícita posible.**

## Explicitar lo implícito {#make-the-implicit-explicit}

Xcode soporta configuraciones implícitas. Un buen ejemplo de ello es inferir las
dependencias definidas implícitamente. Mientras que la implicitud está bien para
proyectos pequeños, donde las configuraciones son simples, a medida que los
proyectos se hacen más grandes puede causar lentitud o comportamientos extraños.

Tuist debería proporcionar APIs explícitas para los comportamientos implícitos
de Xcode. También debería soportar la definición de implícitos de Xcode, pero
implementado de tal manera que anime a los desarrolladores a optar por el
enfoque explícito. Apoyar las implícitas de Xcode y sus complejidades facilita
la adopción de Tuist, después de lo cual los equipos pueden tomar algún tiempo
para deshacerse de las implícitas.

La definición de dependencias es un buen ejemplo de ello. Aunque los
desarrolladores pueden definir las dependencias a través de la configuración y
las fases de compilación, Tuist proporciona una bonita API que fomenta su
adopción.

**Diseñar la API para que sea explícita permite a Tuist ejecutar algunas
comprobaciones y optimizaciones en los proyectos que de otro modo no serían
posibles.** Además, permite funciones como `tuist graph`, que exporta una
representación del gráfico de dependencias, o `tuist cache`, que almacena en
caché todos los objetivos como binarios.

::: consejo
<!-- -->
Deberíamos tratar cada solicitud de portar funciones de Xcode como una
oportunidad para simplificar conceptos con API sencillas y explícitas.
<!-- -->
:::

## Que sea sencillo {#keep-it-simple}

Uno de los principales retos a la hora de escalar proyectos Xcode viene del
hecho de que **Xcode expone mucha complejidad a los usuarios.** Debido a eso,
los equipos tienen un alto factor de bus y sólo unas pocas personas en el equipo
entienden el proyecto y los errores que arroja el sistema de compilación. Esa es
una mala situación para estar porque el equipo depende de unas pocas personas.

Xcode es una gran herramienta, pero tantos años de mejoras, nuevas plataformas y
lenguajes de programación se reflejan en su superficie, que lucha por seguir
siendo sencilla.

Tuist debería aprovechar la oportunidad de mantener las cosas sencillas porque
trabajar en cosas sencillas es divertido y nos motiva. Nadie quiere perder el
tiempo tratando de depurar un error que se produce al final del proceso de
compilación, o entender por qué no son capaces de ejecutar la aplicación en sus
dispositivos. Xcode delega las tareas a su sistema de compilación subyacente y
en algunos casos hace un trabajo muy pobre traduciendo los errores en elementos
procesables. ¿Alguna vez has recibido un error en *"framework X not found"* y no
has sabido qué hacer? Imagina que tuviéramos una lista de las posibles causas
del error.

## Partir de la experiencia del promotor {#start-from-the-developers-experience}

Parte de la razón por la que hay una falta de innovación en torno a Xcode, o
dicho de otro modo, no tanta como en otros entornos de programación, es porque
**solemos empezar a analizar los problemas a partir de soluciones ya
existentes.** Como consecuencia, la mayoría de las soluciones que encontramos
hoy en día giran en torno a las mismas ideas y flujos de trabajo. Aunque es
bueno incluir soluciones existentes en las ecuaciones, no debemos dejar que
limiten nuestra creatividad.

Nos gusta pensar como dice [Tom Preston](https://tom.preston-werner.com/) en
[este podcast](https://tom.preston-werner.com/): *"La mayoría de las cosas se
pueden conseguir, cualquier cosa que tengas en la cabeza probablemente puedas
llevarla a cabo con código siempre que sea posible dentro de las limitaciones
del universo".* Si **imaginamos cómo nos gustaría que fuera la experiencia del
desarrollador**, sólo es cuestión de tiempo conseguirlo: empezar a analizar los
problemas desde la experiencia del desarrollador nos da un punto de vista único
que nos llevará a soluciones que a los usuarios les encantará utilizar.

Podríamos sentirnos tentados de seguir lo que hace todo el mundo, aunque eso
signifique aguantar los inconvenientes de los que todo el mundo sigue
quejándose. No lo hagamos. ¿Cómo me imagino archivando mi aplicación? ¿Cómo me
gustaría que fuera la firma de código? ¿Qué procesos puedo ayudar a agilizar con
Tuist? Por ejemplo, añadir soporte para [Fastlane](https://fastlane.tools/) es
una solución a un problema que tenemos que entender primero. Podemos llegar a la
raíz del problema haciendo preguntas del tipo "¿por qué? Una vez que acotamos de
dónde viene la motivación, podemos pensar en cómo Tuist puede ayudarles mejor.
Quizá la solución sea integrarse en Fastlane, pero es importante que no
despreciemos otras soluciones igualmente válidas que podemos poner sobre la mesa
antes de hacer concesiones.

## Los errores pueden ocurrir y ocurrirán {#errors-can-and-will-happen}

Nosotros, los desarrolladores, tenemos la tentación inherente de ignorar que
pueden producirse errores. Como resultado, diseñamos y probamos el software
teniendo en cuenta únicamente el escenario ideal.

Swift, su sistema de tipos y un código bien diseñado pueden ayudar a prevenir
algunos errores, pero no todos, porque algunos están fuera de nuestro control.
No podemos asumir que el usuario siempre tendrá conexión a Internet, o que los
comandos del sistema volverán con éxito. Los entornos en los que se ejecuta
Tuist no son cajas de arena que controlemos, y por eso tenemos que hacer un
esfuerzo para entender cómo pueden cambiar y afectar a Tuist.

Los errores mal gestionados dan lugar a una mala experiencia de usuario, y los
usuarios pueden perder la confianza en el proyecto. Queremos que los usuarios
disfruten de cada pieza de Tuist, incluso de la forma en que les presentamos los
errores.

Deberíamos ponernos en la piel de los usuarios e imaginar qué esperaríamos que
nos dijera el error. Si el lenguaje de programación es el canal de comunicación
por el que se propagan los errores, y los usuarios son el destino de los
errores, éstos deberían estar escritos en el mismo idioma que hablan los
destinatarios (los usuarios). Deben incluir información suficiente para saber
qué ha pasado y ocultar la información que no sea relevante. Además, deben ser
procesables, indicando a los usuarios los pasos que pueden dar para recuperarse
de ellos.

Y por último, pero no menos importante, nuestros casos de prueba deben
contemplar escenarios de fallo. No solo garantizan que estamos gestionando los
errores como se supone que debemos, sino que evitan que futuros desarrolladores
rompan esa lógica.
