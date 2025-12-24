---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Pruebas selectivas {#selective-testing}

A medida que tu proyecto crece, también lo hace la cantidad de tus pruebas.
Durante mucho tiempo, la ejecución de todas las pruebas en cada PR o empuje a
`principal` toma decenas de segundos. Pero esta solución no es escalable a miles
de pruebas que pueda tener tu equipo.

En cada ejecución de prueba en el CI, lo más probable es que vuelva a ejecutar
todas las pruebas, independientemente de los cambios. Las pruebas selectivas de
Tuist te ayudan a acelerar drásticamente la ejecución de las pruebas en sí,
ejecutando solo las pruebas que han cambiado desde la última ejecución
satisfactoria basada en nuestro algoritmo
<LocalizedLink href="/guides/features/projects/hashing">hashing</LocalizedLink>.

Las pruebas selectivas funcionan con `xcodebuild`, que soporta cualquier
proyecto Xcode, o si generas tus proyectos con Tuist, puedes usar en su lugar el
comando `tuist test` que proporciona algunas comodidades extra como la
integración con la <LocalizedLink href="/guides/features/cache">cache binaria</LocalizedLink>. Para empezar con las pruebas selectivas, siga las
instrucciones basadas en la configuración de su proyecto:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated project</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Debido a la imposibilidad de detectar las dependencias dentro del código entre
las pruebas y las fuentes, la granularidad máxima de las pruebas selectivas es a
nivel de objetivo. Por lo tanto, recomendamos mantener los objetivos pequeños y
centrados para maximizar los beneficios de las pruebas selectivas.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Las herramientas de cobertura de pruebas asumen que todo el conjunto de pruebas
se ejecuta a la vez, lo que las hace incompatibles con las ejecuciones de
pruebas selectivas; esto significa que los datos de cobertura podrían no
reflejar la realidad cuando se utiliza la selección de pruebas. Se trata de una
limitación conocida y no significa que se esté haciendo nada mal. Animamos a los
equipos a reflexionar sobre si la cobertura sigue aportando información
significativa en este contexto y, si es así, ten por seguro que ya estamos
pensando en cómo hacer que la cobertura funcione correctamente con ejecuciones
selectivas en el futuro.
<!-- -->
:::


## Comentarios a las solicitudes de extracción/fusión {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Para obtener comentarios automáticos de pull/merge request, integra tu proyecto
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
con una plataforma
<LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.
<!-- -->
:::

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git como
[GitHub](https://github.com), y empieces a usar `tuist xcodebuild test` o `tuist
test` como parte de tu flujo de trabajo CI, Tuist publicará un comentario
directamente en tus pull/merge requests, incluyendo qué pruebas se ejecutaron y
cuáles se saltaron: ![GitHub app comment with a Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
