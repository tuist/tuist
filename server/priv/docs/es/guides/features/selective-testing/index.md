---
{
  "title": "Tests selectivos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests afectados por tus últimos cambios con los Tests Selectivos de Tuist, para que la integración continua reciba feedback en segundos."
}
---
# Tests selectivos {#selective-testing}

A medida que los proyectos crecen, ejecutar todos los tests en cada push deja de ser viable. Tuist Selective Testing reduce drásticamente el tiempo de tests ejecutando solo aquellos afectados por los cambios desde la última ejecución exitosa, mediante nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>.

## Sistemas de compilación compatibles {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Se planea añadir compatibilidad con otros sistemas de compilación.
