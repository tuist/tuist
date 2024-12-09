---
title: Code reviews
titleTemplate: :title · Contributors · Tuist
description: Learn how to contribute to Tuist by reviewing code
---

# Code reviews {#code-reviews}

La revisión de PRs es una forma típica de contribuir con el proyecto. A pesar de la integración continua (CI) validando que el código hace lo que se supone que tiene que hacer, no es suficiente. Hay rasgos de contribución que no se pueden automatizar: diseño, estructura de código y arquitectura, calidad de las pruebas, o errores tipográficos. Las siguientes secciones representan diferentes aspectos del proceso de revisión de código.

## Legibilidad {#readability}

¿Expresa el código claramente su intención? **Si necesitas dedicar un montón de tiempo a averiguar lo que hace el código, es necesario mejorar la implementación de código.** Sugiere dividir el código en abstracciones más pequeñas que son más fáciles de entender. De forma alternativa y como último recurso, pueden añadir un comentario explicando el razonamiento detrás de él. Pregúntate si serías capaz de entender el código en un futuro próximo, sin ningún contexto circundante como la descripción del pull request.

## Small pull requests {#small-pull-requests}

PRs grandes son difíciles de revisar y es más probable que se escapen detalles. Si un PR acaba siendo muy grande e inmanejable, sugiere al autor que lo divida en PRs más pequeños.

> [!NOTE] EXCEPCIONES
> Hay pocos escenarios donde no es posible dividir el PR, como cuando los cambios están fuertemente acoplados y no pueden ser divididos. En esos casos, el autor debe dar una explicación clara de los cambios y del razonamiento que se esconden detrás de ellos.

## Consistencia {#consistency}

It’s important that the changes are consistent with the rest of the project. Inconsistencies complicate maintenance, and therefore we should avoid them. If there’s an approach to output messages to the user, or report errors, we should stick to that. If the author disagrees with the project’s standards, suggest them to open an issue where we can discuss them further.

## Tests {#tests}

Tests allow changing code with confidence. The code on pull requests should be tested, and all tests should pass. A good test is a test that consistently produces the same result and that it’s easy to understand and maintain. Reviewers spend most of the review time in the implementation code, but tests are equally important because they are code too.

## Breaking changes {#breaking-changes}

Breaking changes are a bad user experience for users of Tuist. Contributions should avoid introducing breaking changes unless it’s strictly necessary. There are many language features that we can leverage to evolve the interface of Tuist without resorting to a breaking change. Whether a change is breaking or not might not be obvious. A method to verify whether the change is breaking is running Tuist against the fixture projects in the fixtures directory. It requires putting ourselves in the user’s shoes and imagine how the changes would impact them.
