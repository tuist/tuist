---
{
  "title": "Instalar Tuist",
  "titleTemplate": ":title · Guías · Tuist",
  "description": "Instala la interfaz de línea de comandos de Tuist en macOS o Linux con mise o Homebrew, y fija una versión para equipos e integración continua."
}
---
# Instalar Tuist {#install-tuist}

La interfaz de línea de comandos de Tuist funciona en **macOS** y **Linux** y conecta tus proyectos de Xcode, generados, Gradle, Bazel y Rust con la infraestructura de caché, análisis y runners de Tuist. Aunque puedes compilar Tuist desde el [código fuente](https://github.com/tuist/tuist), recomendamos uno de los métodos de instalación siguientes para garantizar una instalación válida y verificable. Los proyectos de Elixir usan en su lugar el paquete Hex `tuist_ex` y no necesitan la CLI.

## Mise {#recommended-mise}

> [!NOTE]
> Si no tienes Mise instalado, sigue primero la [guía de inicio](https://mise.jdx.dev/getting-started.html). Mise es una alternativa recomendada a [Homebrew](https://brew.sh) si formas parte de un equipo u organización que necesita garantizar versiones deterministas de las herramientas en distintos entornos.


A diferencia de herramientas como Homebrew, que instalan y activan una única versión de la herramienta de forma global, **Mise fija una versión** ya sea globalmente o limitada a un proyecto. Ejecuta `mise use` para instalar y activar Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Si clonas un proyecto que ya tiene una versión de Tuist fijada en `mise.toml`, ejecuta `mise install` para instalarla.

> [!TIP]
> `tuist@latest` se resuelve a la última versión **estable**. Tuist también publica compilaciones de prerelease tipo canary y release candidate; estas son solo opcionales y nunca se resuelven mediante `latest`. Consulta <.localized_link href="/cli/release/channels">Canales de lanzamiento</.localized_link> para saber cómo fijar una línea estable de confianza y cómo optar por las prereleases.

<details>
<summary>Compatibilidad con Linux</summary>

En Linux, Tuist está disponible exclusivamente a través de Mise. Los comandos que dependen de Xcode (como `tuist generate`) no están disponibles en Linux, pero los comandos independientes de la plataforma, como `tuist inspect bundle`, funcionan como se espera.

</details>


## Homebrew (solo macOS) {#recommended-homebrew}

Puedes instalar Tuist usando [Homebrew](https://brew.sh) y [nuestras fórmulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **Verificar la autenticidad de los binarios**
>
> Puedes verificar que los binarios de tu instalación han sido construidos por nosotros ejecutando el siguiente comando, que comprueba si el equipo del certificado es `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## Proxy HTTP {#http-proxy}

Si tu red enruta el tráfico saliente a través de un proxy HTTP, consulta la <.localized_link href="/guides/integrations/http-proxy">guía de proxy HTTP</.localized_link>.

## Próximos pasos {#next-steps}

- Sigue la <.localized_link href="/guides/get-started">guía de inicio</.localized_link> para conectar tu proyecto a Tuist.
- Explora [la infraestructura de compilación de Tuist para equipos de ingeniería y agentes de programación](https://tuist.dev) para conocer el contexto más amplio del producto.
