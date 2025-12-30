---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Instalar Tuist {#install-tuist}

La CLI de Tuist consta de un ejecutable, frameworks dinámicos y un conjunto de
recursos (por ejemplo, plantillas). Aunque podrías compilar Tuist manualmente
desde [las fuentes](https://github.com/tuist/tuist), **recomendamos usar uno de
los siguientes métodos de instalación para asegurar una instalación válida.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
Mise es una alternativa recomendada a [Homebrew](https://brew.sh) si eres un
equipo u organización que necesita asegurar versiones deterministas de
herramientas a través de diferentes entornos.
<!-- -->
:::

Puedes instalar Tuist a través de cualquiera de los siguientes comandos:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Tenga en cuenta que, a diferencia de herramientas como Homebrew, que instalan y
activan una única versión de la herramienta a nivel global, **Mise requiere la
activación de una versión** ya sea a nivel global o limitada a un proyecto. Esto
se hace ejecutando `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Puedes instalar Tuist usando [Homebrew](https://brew.sh) y [nuestras
fórmulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
Puede verificar que los binarios de su instalación han sido creados por nosotros
ejecutando el siguiente comando, que comprueba si el equipo del certificado es
`U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
