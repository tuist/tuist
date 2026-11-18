---
{
  "title": "Revisiones de código",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Aprende a contribuir a Tuist revisando código"
}
---
# Revisiones de código {#code-reviews}

Revisar pull requests es un tipo común de contribución. Aunque la integración continua (CI) garantiza que el código haga lo que debe, no es suficiente. Hay aspectos de las contribuciones que no se pueden automatizar: diseño, estructura y arquitectura del código, calidad de los tests o erratas. Las siguientes secciones representan diferentes aspectos del proceso de revisión de código.

## Legibilidad {#readability}

¿El código expresa su intención con claridad? **Si necesitas dedicar mucho tiempo a entender qué hace el código, la implementación debe mejorarse.** Sugiere dividir el código en abstracciones más pequeñas que sean más fáciles de entender. Como alternativa, y como último recurso, se puede añadir un comentario que explique el razonamiento detrás. Pregúntate si podrías entender el código en un futuro cercano, sin ningún contexto adicional como la descripción del pull request.

## Pull requests pequeños {#small-pull-requests}

Los pull requests grandes son difíciles de revisar y es más fácil pasar por alto detalles. Si un pull request se vuelve demasiado grande e inmanejable, sugiere al autor que lo divida.

> [!NOTE]
> **Excepciones**
>
> Hay pocos escenarios en los que no es posible dividir el pull request, como cuando los cambios están estrechamente acoplados y no se pueden separar. En esos casos, el autor debe proporcionar una explicación clara de los cambios y del razonamiento detrás de ellos.


## Coherencia {#consistency}

Es importante que los cambios sean coherentes con el resto del proyecto. Las incoherencias complican el mantenimiento, por lo que debemos evitarlas. Si existe un enfoque para mostrar mensajes al usuario o informar errores, debemos seguirlo. Si el autor no está de acuerdo con los estándares del proyecto, sugiérele que abra una issue donde podamos debatirlo más a fondo.

## Tests {#tests}

Los tests permiten cambiar el código con confianza. El código de los pull requests debe estar testeado y todos los tests deben pasar. Un buen test es aquel que produce consistentemente el mismo resultado y es fácil de entender y mantener. Los revisores dedican la mayor parte del tiempo de revisión al código de implementación, pero los tests son igual de importantes porque también son código.

## Cambios incompatibles {#breaking-changes}

Los cambios incompatibles ofrecen una mala experiencia a quienes usan Tuist. Las contribuciones deben evitar introducir cambios incompatibles a menos que sea estrictamente necesario. Existen muchas características del lenguaje que podemos aprovechar para evolucionar la interfaz de Tuist sin recurrir a un cambio incompatible. No siempre es obvio si un cambio es incompatible o no. Un método para verificarlo es ejecutar Tuist contra los proyectos de ejemplo del directorio fixtures. Requiere ponerse en el lugar de la persona usuaria e imaginar cómo le afectarían los cambios.
