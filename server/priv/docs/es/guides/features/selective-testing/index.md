---
{
  "title": "Tests selectivos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests afectados por tus últimos cambios con Tests selectivos de Tuist, para que la integración continua entregue feedback en segundos."
}
---
# Tests selectivos {#selective-testing}

A medida que los proyectos crecen, ejecutar todos los tests en cada push deja de ser viable. Tuist Selective Testing reduce drásticamente el tiempo de ejecución de los tests ejecutando solo aquellos afectados por los cambios desde la última ejecución exitosa, mediante nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>. Para otras formas de reducir el tiempo de los tests, como el sharding y la optimización de tests lentos, consulta [Slow tests](https://tuist.dev/solutions/slow-tests).

## Sistemas de compilación compatibles {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

Se prevé añadir compatibilidad con otros sistemas de compilación.
