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

Para ejecutar pruebas de forma selectiva con tu
<LocalizedLink href="/guides/features/projects">proyecto
generado</LocalizedLink>, utiliza el comando `tuist test`. El comando
<LocalizedLink href="/guides/features/projects/hashing">hash</LocalizedLink> tu
proyecto Xcode de la misma manera que lo hace con la
<LocalizedLink href="/guides/features/cache/module-cache">caché del
módulo</LocalizedLink>, y si tiene éxito, persiste los hash para determinar qué
ha cambiado en futuras ejecuciones. En futuras ejecuciones, `tuist test` utiliza
de forma transparente los hash para filtrar las pruebas y ejecutar solo aquellas
que hayan cambiado desde la última ejecución exitosa.

`tuist test` se integra directamente con la
<LocalizedLink href="/guides/features/cache/module-cache">caché de
módulos</LocalizedLink> para utilizar tantos binarios de su almacenamiento local
o remoto como sea necesario y mejorar el tiempo de compilación al ejecutar su
conjunto de pruebas. La combinación de pruebas selectivas con el almacenamiento
en caché de módulos puede reducir drásticamente el tiempo que se tarda en
ejecutar las pruebas en su CI.

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

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git, como
[GitHub](https://github.com), y comiences a utilizar `tuist test` como parte de
tu flujo de trabajo de CI, Tuist publicará un comentario directamente en tus
solicitudes de extracción/fusión, incluyendo qué pruebas se ejecutaron y cuáles
se omitieron: ![Comentario de la aplicación GitHub con un enlace de vista previa
de Tuist](/images/guides/features/selective-testing/github-app-comment.png)
