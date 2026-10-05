---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# Caché {#cache}

Los artefactos de compilación no se comparten entre entornos, lo que te obliga a recompilar el mismo código una y otra vez. La funcionalidad de caché de Tuist comparte artefactos de forma remota para que tu equipo y la CI obtengan compilaciones más rápidas sin volver a compilar lo que ya ha sido compilado.

Conoce el flujo de trabajo de caché que se adapta a tu proyecto o modelo de despliegue:

\<.home\_cards\>
\<.home\_card
title="Caché de módulos"
details="Almacena en caché módulos individuales como binarios para proyectos que usan los proyectos generados por Tuist. Requiere la generación de proyectos de Tuist."
link="/guides/features/cache/module-cache"
/\>
\<.home\_card
title="Caché de Xcode"
details="Comparte artefactos de compilación de Xcode entre entornos. Funciona con cualquier proyecto de Xcode, sin necesidad de generar proyectos."
link="/guides/features/cache/xcode-cache"
/\>
\<.home\_card
title="Caché de Gradle"
details="Comparte de forma remota los artefactos de la caché de compilación de Gradle. Incluye información sobre la compilación para tener visibilidad del rendimiento."
link="/guides/features/cache/gradle-cache"
/\>
\<.home\_card
title="Caché de Bazel"
details="Configura Bazel para usar la caché de la API de Ejecución Remota de Tuist y compartir los resultados de las acciones entre tu equipo y la CI."
link="/guides/features/cache/bazel-cache"
/\>
\<.home\_card
title="Autoalojamiento"
details="Ejecuta nodos de caché cerca de la CI, oficinas o computación regional y conéctalos a Tuist alojado o autoalojado."
link="/guides/features/cache/self-hosting"
/\>
\</.home\_cards\>

> \[\!TIP\]
> **Más rápido en Tuist Runners**
> 
> En \<.localized\_link href="/guides/features/runners"\>Tuist Runners\</.localized\_link\>, la caché está ubicada en la red privada del runner y se comparte con la misma caché que usan las máquinas de los desarrolladores, por lo que los trabajos de CI obtienen aciertos en caliente desde el inicio, sin necesidad de calentar una caché de CI separada.

## Restringir subidas a la CI {#restrict-uploads-to-ci}

Los administradores de cuenta pueden configurar a los desarrolladores como solo lectura mientras permiten que la CI suba artefactos a la caché. Abre la configuración de **Caché** de la cuenta en Tuist y establece **Acceso de subida a caché** en **Solo tokens de CI y de cuenta**. Después de esto, los miembros autenticados con sesiones de inicio de sesión aún podrán descargar desde la caché, pero las subidas requerirán autenticación OIDC de CI o un token de cuenta con permisos de escritura en caché, como `project:cache:write` o `ci`.

Utiliza esta opción cuando la CI sea el productor de caché de confianza y las máquinas locales solo deban consumir la caché. La configuración afecta únicamente a la autorización de subida a la caché.