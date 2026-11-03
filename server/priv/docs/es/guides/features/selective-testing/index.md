---
{
  "title": "Tests selectivos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests afectados por tus últimos cambios con los Tests Selectivos de Tuist, para que la integración continua reciba feedback en segundos."
}
---
# Tests selectivos {#selective-testing}

A medida que los proyectos crecen, ejecutar todos los tests en cada push deja de ser viable. Tuist Selective Testing reduce drásticamente el tiempo de ejecución de los tests ejecutando únicamente aquellos afectados por los cambios desde la última ejecución exitosa, utilizando nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>.

## Sistemas de compilación compatibles {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

El soporte para otros sistemas de compilación está planificado.
