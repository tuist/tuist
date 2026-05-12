---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimiza los tiempos de build con Tuist Cache, incluidos el cache de módulos, el cache de Xcode y el cache de Gradle."
}
---
# Cache {#cache}

Los artefactos de build no se comparten entre entornos, lo que te obliga a recompilar el mismo código una y otra vez. La funcionalidad de cache de Tuist comparte artefactos de forma remota para que tu equipo y CI obtengan builds más rápidos sin recompilar lo que ya se ha compilado.

Elige la solución de cache que encaje con tu sistema de build:

<HomeCards>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Cache de módulos"
        details="Cachea módulos individuales como binarios para proyectos que usan los proyectos generados de Tuist. Requiere generación de proyectos de Tuist."
        linkText="Configurar el cache de módulos"
        link="/guides/features/cache/module-cache"/>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Cache de Xcode"
        details="Comparte artefactos de compilación de Xcode entre entornos. Funciona con cualquier proyecto de Xcode, sin requerir generación de proyectos."
        linkText="Configurar el cache de Xcode"
        link="/guides/features/cache/xcode-cache"/>
    <HomeCard
        icon="<img src='/images/guides/features/gradle-icon.svg' alt='Gradle' width='32' height='32' />"
        title="Cache de Gradle"
        details="Comparte artefactos del build cache de Gradle de forma remota. Incluye insights de build para tener visibilidad del rendimiento."
        linkText="Configurar el cache de Gradle"
        link="/guides/features/cache/gradle-cache"/>
</HomeCards>
