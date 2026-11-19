---
{
  "title": "Tests selectivos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests afectados por tus últimos cambios con los tests selectivos de Tuist, para que la integración continua entregue feedback en segundos."
}
---
# Tests selectivos {#selective-testing}

A medida que los proyectos crecen, ejecutar todos los tests en cada push deja de ser viable. Los tests selectivos de Tuist reducen drásticamente el tiempo de prueba ejecutando solo los tests afectados por los cambios desde la última ejecución exitosa, mediante nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>. Para otras formas de reducir el tiempo de prueba, como la fragmentación y la corrección de tests lentos, consulta [Tests lentos](https://tuist.dev/solutions/slow-tests).

## Sistemas de compilación compatibles {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Se planea añadir compatibilidad con otros sistemas de compilación.
