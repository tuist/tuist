---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Principios {#principles}

Esta página describe los principios que son los pilares del diseño y desarrollo
de Tuist. Estos principios evolucionan con el proyecto y tienen como objetivo
garantizar un crecimiento sostenible que esté en consonancia con los fundamentos
del proyecto.

## Siga las convenciones por defecto. {#default-to-conventions}

Una de las razones por las que existe Tuist es porque Xcode es débil en cuanto a
convenciones, lo que da lugar a proyectos complejos que son difíciles de ampliar
y mantener. Por esa razón, Tuist adopta un enfoque diferente al utilizar por
defecto convenciones sencillas y cuidadosamente diseñadas. **Los desarrolladores
pueden optar por no seguir las convenciones, pero se trata de una decisión
consciente que no resulta natural.**

Por ejemplo, existe una convención para definir las dependencias entre los
objetivos utilizando la interfaz pública proporcionada. Al hacerlo, Tuist
garantiza que los proyectos se generen con las configuraciones adecuadas para
que el enlace funcione. Los desarrolladores tienen la opción de definir las
dependencias a través de la configuración de compilación, pero lo harían de
forma implícita y, por lo tanto, romperían las funciones de Tuist, como `tuist
graph` o `tuist cache`, que se basan en el cumplimiento de algunas convenciones.

La razón por la que utilizamos convenciones por defecto es que cuantas más
decisiones podamos tomar en nombre de los desarrolladores, más se podrán centrar
estos en crear funciones para sus aplicaciones. Cuando no disponemos de
convenciones, como ocurre en muchos proyectos, tenemos que tomar decisiones que
acabarán siendo incoherentes con otras decisiones y, como consecuencia, se
producirá una complejidad accidental que será difícil de gestionar.

## Los manifiestos son la fuente de la verdad. {#manifests-are-the-source-of-truth}

Tener muchas capas de configuraciones y contratos entre ellas da como resultado
una configuración del proyecto difícil de entender y mantener. Piense por un
momento en un proyecto medio. La definición del proyecto se encuentra en los
directorios `.xcodeproj`, la CLI en scripts (por ejemplo, `Fastfiles`) y la
lógica de CI en pipelines. Son tres capas con contratos entre ellas que debemos
mantener. *¿Cuántas veces se ha encontrado en una situación en la que ha
cambiado algo en sus proyectos y, una semana después, se ha dado cuenta de que
los scripts de lanzamiento no funcionaban?*

Podemos simplificar esto teniendo una única fuente de verdad, los archivos de
manifiesto. Esos archivos proporcionan a Tuist la información que necesita para
generar proyectos Xcode que los desarrolladores pueden utilizar para editar sus
archivos. Además, permite disponer de comandos estándar para crear proyectos
desde un entorno local o de CI.

**Tuist debe asumir la complejidad y ofrecer una interfaz sencilla, segura y
agradable para describir sus proyectos de la forma más explícita posible.**

## Haz explícito lo implícito. {#make-the-implicit-explicit}

Xcode admite configuraciones implícitas. Un buen ejemplo de ello es la
inferencia de las dependencias definidas implícitamente. Si bien la implícita es
adecuada para proyectos pequeños, en los que las configuraciones son sencillas,
a medida que los proyectos se hacen más grandes puede provocar lentitud o
comportamientos extraños.

Tuist debe proporcionar API explícitas para los comportamientos implícitos de
Xcode. También debe admitir la definición de implícitos de Xcode, pero
implementados de tal manera que anime a los desarrolladores a optar por el
enfoque explícito. Admitir los implícitos y las complejidades de Xcode facilita
la adopción de Tuist, tras lo cual los equipos pueden tomarse un tiempo para
deshacerse de los implícitos.

La definición de dependencias es un buen ejemplo de ello. Aunque los
desarrolladores pueden definir las dependencias a través de la configuración y
las fases de compilación, Tuist proporciona una API muy atractiva que fomenta su
adopción.

**El diseño explícito de la API permite a Tuist realizar algunas comprobaciones
y optimizaciones en los proyectos que de otro modo no serían posibles.** Además,
habilita funciones como `tuist graph`, que exporta una representación del
gráfico de dependencias, o `tuist cache`, que almacena en caché todos los
objetivos como binarios.

::: consejo
<!-- -->
Debemos tratar cada solicitud de transferencia de funciones desde Xcode como una
oportunidad para simplificar conceptos con API sencillas y explícitas.
<!-- -->
:::

## Mantén la sencillez. {#keep-it-simple}

Uno de los principales retos a la hora de escalar proyectos Xcode proviene del
hecho de que **Xcode expone mucha complejidad a los usuarios.** Debido a ello,
los equipos tienen un alto factor de autobús y solo unas pocas personas del
equipo entienden el proyecto y los errores que arroja el sistema de compilación.
Es una mala situación, ya que el equipo depende de unas pocas personas.

Xcode es una herramienta estupenda, pero tantos años de mejoras, nuevas
plataformas y lenguajes de programación se reflejan en su superficie, que luchó
por seguir siendo sencilla.

Tuist debería aprovechar la oportunidad para simplificar las cosas, porque
trabajar en cosas sencillas es divertido y nos motiva. Nadie quiere perder
tiempo intentando depurar un error que se produce al final del proceso de
compilación, o tratando de entender por qué no puede ejecutar la aplicación en
sus dispositivos. Xcode delega las tareas a su sistema de compilación subyacente
y, en algunos casos, hace un trabajo muy deficiente a la hora de traducir los
errores en elementos procesables. ¿Alguna vez ha recibido un error « *»
«framework X not found» «* » y no ha sabido qué hacer? Imagine si tuviéramos una
lista de posibles causas del error.

## Comience desde la experiencia del desarrollador. {#start-from-the-developers-experience}

Parte de la razón por la que hay una falta de innovación en torno a Xcode, o
dicho de otra manera, no tanta como en otros entornos de programación, es porque
**a menudo empezamos a analizar los problemas a partir de soluciones
existentes.** Como consecuencia, la mayoría de las soluciones que encontramos
hoy en día giran en torno a las mismas ideas y flujos de trabajo. Si bien es
bueno incluir las soluciones existentes en las ecuaciones, no debemos permitir
que limiten nuestra creatividad.

Nos gusta pensar como dice [Tom Preston](https://tom.preston-werner.com/) en
[este podcast](https://tom.preston-werner.com/): *«Se puede conseguir casi todo,
cualquier cosa que se te ocurra probablemente se pueda llevar a cabo con código,
siempre que sea posible dentro de las limitaciones del universo».* Si
**imaginamos cómo nos gustaría que fuera la experiencia del desarrollador**, es
solo cuestión de tiempo conseguirlo: empezar a analizar los problemas desde la
experiencia del desarrollador nos da un punto de vista único que nos llevará a
soluciones que a los usuarios les encantará usar.

Podríamos sentirnos tentados a seguir lo que hacen todos los demás, incluso si
eso significa seguir soportando las inconveniencias de las que todos se quejan.
No hagamos eso. ¿Cómo imagino el archivo de mi aplicación? ¿Cómo me gustaría que
fuera la firma de código? ¿Qué procesos puedo ayudar a optimizar con Tuist? Por
ejemplo, añadir compatibilidad con [Fastlane](https://fastlane.tools/) es una
solución a un problema que primero debemos comprender. Podemos llegar a la raíz
del problema haciendo preguntas «por qué». Una vez que hayamos determinado cuál
es la motivación, podemos pensar en cómo Tuist puede ayudarles mejor. Quizás la
solución sea integrarse con Fastlane, pero es importante que no descartemos
otras soluciones igualmente válidas que podemos poner sobre la mesa antes de
hacer concesiones.

## Los errores pueden ocurrir y ocurrirán. {#errors-can-and-will-happen}

Los desarrolladores tenemos una tentación inherente de ignorar que pueden
producirse errores. Como resultado, diseñamos y probamos el software teniendo en
cuenta únicamente el escenario ideal.

Swift, su sistema de tipos y un código bien diseñado pueden ayudar a prevenir
algunos errores, pero no todos, ya que algunos escapan a nuestro control. No
podemos dar por sentado que el usuario siempre tendrá conexión a Internet o que
los comandos del sistema se ejecutarán correctamente. Los entornos en los que se
ejecuta Tuist no son entornos aislados que podamos controlar, por lo que debemos
esforzarnos por comprender cómo pueden cambiar y afectar a Tuist.

Los errores mal gestionados dan lugar a una mala experiencia de usuario, y los
usuarios pueden perder la confianza en el proyecto. Queremos que los usuarios
disfruten de cada parte de Tuist, incluso de la forma en que les presentamos los
errores.

Debemos ponernos en el lugar de los usuarios e imaginar qué esperaríamos que nos
dijera el error. Si el lenguaje de programación es el canal de comunicación a
través del cual se propagan los errores, y los usuarios son el destino de los
errores, estos deben estar escritos en el mismo lenguaje que hablan los
destinatarios (los usuarios). Deben incluir información suficiente para saber
qué ha ocurrido y ocultar la información que no sea relevante. Además, deben ser
prácticos, indicando a los usuarios qué pasos pueden seguir para recuperarse de
ellos.

Y por último, pero no menos importante, nuestros casos de prueba deben
contemplar escenarios fallidos. No solo garantizan que estamos gestionando los
errores como se supone que debemos hacerlo, sino que evitan que los futuros
desarrolladores rompan esa lógica.
