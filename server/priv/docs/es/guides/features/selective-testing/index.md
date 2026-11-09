---
{
  "title": "Tests selectivos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests afectados por tus últimos cambios con Tuist Selective Testing, para que la integración continua entregue feedback en segundos."
}
---
# Tests selectivos {#selective-testing}

A medida que los proyectos crecen, ejecutar todos los tests en cada push deja de ser viable. Los tests selectivos de Tuist reducen drásticamente el tiempo de prueba ejecutando solo los tests afectados por lo que ha cambiado desde la última ejecución exitosa, utilizando nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>.

## Sistemas de compilación compatibles {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

El soporte para otros sistemas de compilación está previsto.
