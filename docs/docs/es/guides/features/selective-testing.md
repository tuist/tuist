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
integración con la <LocalizedLink href="/guides/features/cache">cache
binaria</LocalizedLink>. Para empezar con las pruebas selectivas, siga las
instrucciones basadas en la configuración de su proyecto:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated
  project</LocalizedLink>

> [Debido a la imposibilidad de detectar las dependencias dentro del código
> entre pruebas y fuentes, la granularidad máxima de las pruebas selectivas es a
> nivel de objetivo. Por lo tanto, recomendamos mantener sus objetivos pequeños
> y enfocados para maximizar los beneficios de las pruebas selectivas.

> [COBERTURA DE PRUEBAS Las herramientas de cobertura de pruebas asumen que todo
> el conjunto de pruebas se ejecuta a la vez, lo que las hace incompatibles con
> las ejecuciones de pruebas selectivas, lo que significa que los datos de
> cobertura podrían no reflejar la realidad cuando se utiliza la selección de
> pruebas. Se trata de una limitación conocida y no significa que se esté
> haciendo nada mal. Animamos a los equipos a reflexionar sobre si la cobertura
> sigue aportando información significativa en este contexto y, si es así, ten
> por seguro que ya estamos pensando en cómo hacer que la cobertura funcione
> correctamente con ejecuciones selectivas en el futuro.


## Comentarios de solicitudes pull/merge {#pullmerge-request-comments}

> [IMPORTANTE] INTEGRACIÓN CON PLATAFORMA GIT REQUERIDA Para obtener comentarios
> automáticos en las solicitudes pull/merge, integra tu proyecto
> <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
> con una plataforma
> <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git, como
[GitHub](https://github.com), y empieces a usar `tuist xcodebuild test` o `tuist
test` como parte de tu flujo de trabajo CI, Tuist publicará un comentario
directamente en tus pull/merge requests, incluyendo qué pruebas se han ejecutado
y cuáles se han omitido: ![GitHub app comment with a Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
