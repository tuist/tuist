---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Revisiones de códigos {#code-reviews}

La revisión de pull requests es un tipo de contribución habitual. A pesar de que
la integración continua (IC) garantiza que el código hace lo que se supone que
debe hacer, no es suficiente. Hay aspectos de la contribución que no pueden
automatizarse: el diseño, la estructura y arquitectura del código, la calidad de
las pruebas o los errores tipográficos. Las siguientes secciones representan
distintos aspectos del proceso de revisión del código.

## Legibilidad {#readability}

¿Expresa el código su intención con claridad? **Si tienes que dedicar mucho
tiempo a averiguar qué hace el código, es que hay que mejorar su
implementación.** Sugiera dividir el código en abstracciones más pequeñas que
sean más fáciles de entender. Alternativamente, y como último recurso, pueden
añadir un comentario explicando el razonamiento que hay detrás. Pregúntate si
serías capaz de entender el código en un futuro cercano, sin ningún contexto
circundante como la descripción del pull request.

## Pequeños pull requests {#small-pull-requests}

Los pull requests grandes son difíciles de revisar y es más fácil perderse
detalles. Si una pull request se vuelve demasiado grande e inmanejable, sugiera
al autor que la divida.

::: info EXCEPCIONES
<!-- -->
Hay algunos casos en los que no es posible dividir la solicitud de extracción,
como cuando los cambios están estrechamente vinculados y no pueden dividirse. En
esos casos, el autor debe proporcionar una explicación clara de los cambios y el
razonamiento detrás de ellos.
<!-- -->
:::

## Coherencia {#consistency}

Es importante que los cambios sean coherentes con el resto del proyecto. Las
incoherencias complican el mantenimiento, por lo que debemos evitarlas. Si hay
un enfoque para mostrar mensajes al usuario, o informar de errores, deberíamos
ceñirnos a él. Si el autor no está de acuerdo con las normas del proyecto,
sugiérale que abra una incidencia en la que podamos discutirlo más a fondo.

## Pruebas {#tests}

Las pruebas permiten cambiar el código con confianza. El código de los pull
requests debe probarse, y todas las pruebas deben pasar. Una buena prueba es una
prueba que produce sistemáticamente el mismo resultado y que es fácil de
entender y mantener. Los revisores pasan la mayor parte del tiempo de revisión
en el código de implementación, pero las pruebas son igualmente importantes
porque también son código.

## Cambios de última hora {#breaking-changes}

Los cambios de última hora son una mala experiencia para los usuarios de Tuist.
Las contribuciones deberían evitar introducir cambios de ruptura a menos que sea
estrictamente necesario. Hay muchas características del lenguaje que podemos
aprovechar para evolucionar la interfaz de Tuist sin recurrir a un cambio de
ruptura. Si un cambio es de ruptura o no puede no ser obvio. Un método para
verificar si el cambio está rompiendo es ejecutar Tuist contra los proyectos de
fixture en el directorio fixtures. Requiere ponernos en la piel del usuario e
imaginar cómo le afectarían los cambios.
