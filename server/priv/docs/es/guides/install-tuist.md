---
{
  "title": "Instalar Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Aprende a instalar Tuist en tu entorno."
}
---
# Instalar Tuist {#install-tuist}

Tuist se ejecuta en **macOS** y **Linux**. Aunque podrías compilar Tuist manualmente desde [el código fuente](https://github.com/tuist/tuist), **te recomendamos usar uno de los siguientes métodos de instalación para garantizar una instalación válida.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> Si no tienes Mise instalado, sigue primero la [guía de primeros pasos](https://mise.jdx.dev/getting-started.html). Mise es una alternativa recomendada a [Homebrew](https://brew.sh) si eres parte de un equipo u organización que necesita garantizar versiones deterministas de herramientas entre distintos entornos.


A diferencia de herramientas como Homebrew, que instalan y activan una única versión de la herramienta de forma global, **Mise fija una versión** globalmente o limitada a un proyecto. Ejecuta `mise use` para instalar y activar Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Si clonas un proyecto que ya tiene una versión de Tuist fijada en `mise.toml`, ejecuta `mise install` para instalarla.

<details>
<summary>Compatibilidad con Linux</summary>

En Linux, Tuist está disponible exclusivamente mediante Mise. Los comandos que dependen de Xcode, como `tuist generate`, no están disponibles en Linux, pero los comandos independientes de la plataforma como `tuist inspect bundle` funcionan como se espera.

</details>


### <a href="https://brew.sh">Homebrew</a> (solo macOS) {#recommended-homebrew}

Puedes instalar Tuist usando [Homebrew](https://brew.sh) y [nuestras fórmulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **Verificar la autenticidad de los binarios**
>
> Puedes verificar que los binarios de tu instalación han sido compilados por nosotros ejecutando el siguiente comando, que comprueba si el equipo del certificado es `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP proxy {#http-proxy}

Si tu red enruta el tráfico saliente a través de un HTTP proxy, consulta la <.localized_link href="/guides/integrations/http-proxy">guía de HTTP proxy</.localized_link>.
