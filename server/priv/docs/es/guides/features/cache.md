---
{
  "title": "Caché",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Optimiza los tiempos de compilación con Tuist Cache para Xcode, Gradle, Bazel, Elixir, Rust y Struo."
}
---
# Caché {#cache}

Los artefactos de compilación no se comparten entre entornos, lo que te obliga a recompilar el mismo código una y otra vez. La funcionalidad de caché de Tuist comparte los artefactos de forma remota para que tu equipo y la CI obtengan compilaciones más rápidas sin volver a compilar lo que ya está compilado. Para saber cómo funcionan las cachés de compilación locales y remotas en distintos sistemas de compilación, y qué son las propias cachés de Xcode, consulta <.localized_link href="/references/concepts/build-cache">¿Qué es una caché de compilación?</.localized_link>. Para averiguar por qué las compilaciones son lentas antes de elegir una caché, consulta [Compilaciones lentas](https://tuist.dev/solutions/slow-builds).

Conoce el flujo de trabajo de caché que mejor se adapta a tu proyecto o modelo de despliegue:

<.home_cards>
  <.home_card
    title="Caché de módulos"
    details="Almacena en caché módulos individuales como binarios para proyectos que usan los proyectos generados por Tuist. Requiere la generación de proyectos con Tuist."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Caché de Xcode"
    details="Comparte artefactos de compilación de Xcode entre entornos. Funciona con cualquier proyecto de Xcode, sin necesidad de generar el proyecto."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Caché de Gradle"
    details="Comparte artefactos de la caché de compilación de Gradle de forma remota. Incluye análisis de compilaciones para visibilidad del rendimiento."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Caché de Bazel"
    details="Configura Bazel para usar la caché de la API de Ejecución Remota de Tuist y compartir los resultados de las acciones entre tu equipo y la CI."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Caché de Elixir"
    details="Habilita la caché para las dependencias de Elixir compatibles y sigue usando Mix. Inspecciona los aciertos de caché y las transferencias en el panel."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Caché de Rust (experimental)"
    details="Reutiliza los resultados de compilación de Rust compatibles y las ejecuciones de scripts de compilación de forma local y a través de Kura. Aprende a habilitar la caché e inspeccionar su actividad."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Caché de Struo"
    details="Comparte los resultados en caché de scripts y acciones del grafo entre las máquinas de desarrollo y la CI con el proveedor nativo de Tuist de Struo."
    link="/guides/features/cache/struo"
/>
  <.home_card
    title="Autoalojamiento"
    details="Ejecuta nodos de caché cerca de la CI, oficinas o infraestructura regional y conéctalos a Tuist alojado o autoalojado."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Máxima velocidad en Tuist Runners**
>
> En <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, la caché está ubicada en la red privada del runner y se comparte con la misma caché que usan tus máquinas de desarrollo, por lo que los trabajos de CI obtienen aciertos en caliente desde el primer momento, sin necesidad de calentar una caché de CI separada.


## Restringir subidas a la CI {#restrict-uploads-to-ci}

Los administradores de cuenta pueden configurar a los desarrolladores como solo lectura mientras permiten que la CI suba artefactos de caché. Abre la configuración de **Caché** de la cuenta en Tuist y establece **Acceso de subida a caché** en **Solo tokens de CI y de cuenta**. Después, los miembros autenticados con sesiones de inicio seguirán pudiendo descargar de la caché, pero las subidas requieren autenticación OIDC de CI o un token de cuenta con permisos de escritura en caché, como `project:cache:write` o `ci`.

Usa esta opción cuando la CI sea el productor de caché de confianza y las máquinas locales deban solo consumir la caché. La configuración afecta únicamente a la autorización de subida a la caché.
