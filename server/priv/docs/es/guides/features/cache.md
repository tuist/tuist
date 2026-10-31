---
{
  "title": "Caché",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Optimiza los tiempos de compilación con la caché de Tuist, incluyendo la caché de módulos, la caché de Xcode, la caché de Gradle, la caché de Bazel, la caché de dependencias de Elixir y la caché experimental de compilación de Rust."
}
---
# Caché {#cache}

Los artefactos de compilación no se comparten entre entornos, lo que te obliga a recompilar el mismo código una y otra vez. La función de caché de Tuist comparte los artefactos de forma remota para que tu equipo y la CI obtengan compilaciones más rápidas sin volver a compilar lo que ya está compilado.

Conoce el flujo de trabajo de caché que se adapta a tu proyecto o modelo de despliegue:

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
    details="Apunta Bazel a la caché de la API de ejecución remota de Tuist para compartir los resultados de las acciones entre tu equipo y la CI."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Caché de Elixir"
    details="Habilita la caché para las dependencias de Elixir compatibles y sigue usando Mix. Inspecciona los aciertos de caché y las transferencias en el panel."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Caché de Rust (experimental)"
    details="Reutiliza localmente y a través de Kura los resultados de las bibliotecas hoja del registro compatibles. Aprende cómo habilitar la caché e inspeccionar la actividad de la caché."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Autoalojamiento"
    details="Ejecuta nodos de caché cerca de la CI, las oficinas o la computación regional y conéctalos a Tuist alojado o autoalojado."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Más rápido en Tuist Runners**
>
> En <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, la caché está ubicada en la red privada del runner y se comparte con la misma caché que usan tus máquinas de desarrollo, por lo que los trabajos de CI obtienen aciertos cálidos desde el primer momento, sin necesidad de calentar una caché de CI separada.


## Restringir las subidas a la CI {#restrict-uploads-to-ci}

Los administradores de la cuenta pueden configurar a los desarrolladores como solo lectura mientras permiten que la CI suba artefactos de caché. Abre la configuración de **Caché** de la cuenta en Tuist y establece **Acceso de subida a la caché** en **Solo tokens de CI y de cuenta**. Después de eso, los miembros autenticados con sesiones de inicio seguirán pudiendo descargar de la caché, pero las subidas requieren autenticación OIDC de CI o un token de cuenta con permisos de escritura en la caché, como `project:cache:write` o `ci`.

Usa esta opción cuando la CI sea el productor de caché de confianza y las máquinas locales deban solo consumir la caché. La configuración afecta únicamente a la autorización de subida a la caché.
