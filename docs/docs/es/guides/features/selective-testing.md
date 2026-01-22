---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Pruebas selectivas {#selective-testing}

A medida que tu proyecto crece, también lo hace la cantidad de pruebas. Durante
mucho tiempo, ejecutar todas las pruebas en cada PR o push a `main` lleva
decenas de segundos. Pero esta solución no se adapta a los miles de pruebas que
tu equipo podría tener.

En cada ejecución de pruebas en la CI, lo más probable es que vuelva a ejecutar
todas las pruebas, independientemente de los cambios. Las pruebas selectivas de
Tuist le ayudan a acelerar drásticamente la ejecución de las pruebas, ya que
solo se ejecutan aquellas que han cambiado desde la última ejecución
satisfactoria, basándose en nuestro algoritmo de hash
<LocalizedLink href="/guides/features/projects/hashing">.

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Debido a la imposibilidad de detectar las dependencias en el código entre las
pruebas y las fuentes, la granularidad máxima de las pruebas selectivas se
encuentra en el nivel de destino. Por lo tanto, recomendamos mantener los
destinos pequeños y específicos para maximizar los beneficios de las pruebas
selectivas.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Las herramientas de cobertura de pruebas asumen que todo el conjunto de pruebas
se ejecuta de una sola vez, lo que las hace incompatibles con las ejecuciones de
pruebas selectivas, lo que significa que los datos de cobertura podrían no
reflejar la realidad cuando se utiliza la selección de pruebas. Se trata de una
limitación conocida y no significa que estés haciendo nada mal. Animamos a los
equipos a que reflexionen sobre si la cobertura sigue aportando información
significativa en este contexto y, si es así, pueden estar seguros de que ya
estamos pensando en cómo hacer que la cobertura funcione correctamente con
ejecuciones selectivas en el futuro.
<!-- -->
:::


## Comentarios sobre solicitudes de extracción/fusión {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Para obtener comentarios automáticos de solicitudes de extracción/fusión,
integra tu <LocalizedLink href="/guides/server/accounts-and-projects">proyecto
Tuist</LocalizedLink> con una
<LocalizedLink href="/guides/server/authentication">plataforma
Git</LocalizedLink>.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
