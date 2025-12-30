---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Caché {#cache}

El sistema de compilación de Xcode proporciona [compilaciones
incrementales](https://en.wikipedia.org/wiki/Incremental_build_model), mejorando
la eficiencia en una sola máquina. Sin embargo, los artefactos de compilación no
se comparten entre distintos entornos, lo que te obliga a reconstruir el mismo
código una y otra vez, ya sea en tus entornos de [integración continua
(CI)](https://en.wikipedia.org/wiki/Continuous_integration) o de desarrollo
local (tu Mac).

Tuist aborda estos retos con su función de almacenamiento en caché, reduciendo
significativamente los tiempos de compilación tanto en entornos de desarrollo
local como de CI. Este enfoque no solo acelera los bucles de retroalimentación,
sino que también minimiza la necesidad de cambiar de contexto, lo que en última
instancia aumenta la productividad.

Ofrecemos dos tipos de caché:
- <LocalizedLink href="/guides/features/cache/module-cache">Módulo caché</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Caché de Xcode</LocalizedLink>

## Caché de módulos {#module-cache}

Para los proyectos que utilizan las capacidades de generación de
<LocalizedLink href="/guides/features/projects">proyectos</LocalizedLink> de
Tuist, proporcionamos un potente sistema de almacenamiento en caché, que
almacena en caché módulos individuales como binarios y los comparte a través de
su equipo y entornos CI.

Aunque también puede utilizar la nueva caché de Xcode, esta función está
actualmente optimizada para compilaciones locales y es probable que la tasa de
aciertos de la caché sea inferior a la de la caché de proyectos generados. Sin
embargo, la decisión de qué solución de almacenamiento en caché utilizar depende
de sus necesidades y preferencias específicas. También puede combinar ambas
soluciones de almacenamiento en caché para obtener los mejores resultados.

<LocalizedLink href="/guides/features/cache/module-cache">Más información sobre la caché del módulo →</LocalizedLink>

## Caché de Xcode {#xcode-cache}

::: aviso ESTADO DE CACHE EN XCODE
<!-- -->
La caché de Xcode está actualmente optimizada para compilaciones incrementales
locales y todo el espectro de tareas de compilación aún no es independiente de
la ruta. Aún así puedes experimentar beneficios conectando la caché remota de
Tuist, y esperamos que los tiempos de compilación mejoren con el tiempo a medida
que la capacidad del sistema de compilación siga mejorando.
<!-- -->
:::

Apple ha estado trabajando en una nueva solución de almacenamiento en caché a
nivel de compilación, similar a otros sistemas de compilación como Bazel y Buck.
La nueva capacidad de almacenamiento en caché está disponible desde Xcode 26 y
Tuist ahora se integra perfectamente con él - independientemente de si usted
está utilizando Tuist's
<LocalizedLink href="/guides/features/projects">generación de proyectos</LocalizedLink> capacidades o no.

<LocalizedLink href="/guides/features/cache/xcode-cache">Más información sobre la caché de Xcode →</LocalizedLink>
