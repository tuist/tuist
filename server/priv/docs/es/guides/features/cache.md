---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# Caché {#cache}

Los artefactos de compilación no se comparten entre entornos, lo que te obliga a recompilar el mismo código una y otra vez. La funcionalidad de caché de Tuist comparte artefactos de forma remota para que tu equipo y la CI obtengan compilaciones más rápidas sin volver a compilar lo que ya ha sido compilado.

Conoce el flujo de trabajo de caché que se adapta a tu proyecto o modelo de despliegue:

<.home_cards>
  <.home_card
    title="Caché de módulos"
    details="Almacena en caché módulos individuales como binarios para proyectos que utilizan los proyectos generados por Tuist. Requiere la generación de proyectos de Tuist."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Caché de Xcode"
    details="Comparte artefactos de compilación de Xcode entre entornos. Funciona con cualquier proyecto de Xcode, sin necesidad de generar el proyecto."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Caché de Gradle"
    details="Comparte artefactos de la caché de compilación de Gradle de forma remota. Incluye información sobre la compilación para visibilidad del rendimiento."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Caché de Bazel"
    details="Apunta Bazel a la caché de la API de Ejecución Remota de Tuist para compartir las salidas de las acciones entre tu equipo y la CI."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Caché de Elixir"
    details="Habilita la caché para las dependencias de Elixir compatibles y sigue usando Mix. Inspecciona los aciertos y transferencias de caché en el panel de control."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Caché de Rust (experimental)"
    details="Reutiliza localmente y a través de Kura las salidas de las bibliotecas hoja del registro compatibles. Aprende cómo habilitar la caché e inspeccionar la actividad de la caché."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Autoalojamiento"
    details="Ejecuta nodos de caché cerca de la CI, oficinas o computación regional y conéctalos a Tuist alojado o autoalojado."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Más rápido en Tuist Runners**
>
> En <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, la caché está ubicada en la red privada del ejecutor y se comparte con la misma caché que usan tus máquinas de desarrollo, por lo que los trabajos de CI obtienen aciertos en caliente desde el primer momento, sin necesidad de calentar una caché de CI separada.


## Restringir subidas a CI {#restrict-uploads-to-ci}

Los administradores de cuenta pueden configurar a los desarrolladores como solo lectura mientras permiten que la CI suba artefactos de caché. Abre la configuración de **Caché** de la cuenta en Tuist y establece **Acceso de subida a caché** en **Solo tokens de CI y cuenta**. Después de eso, los miembros autenticados con sesiones de inicio de sesión aún pueden descargar desde la caché, pero las subidas requieren autenticación OIDC de CI o un token de cuenta con ámbitos de escritura de caché como `project:cache:write` o `ci`.

Utiliza esta opción cuando la CI sea el productor de caché de confianza y las máquinas locales solo deban consumir la caché. La configuración afecta únicamente a la autorización de subida a la caché.
