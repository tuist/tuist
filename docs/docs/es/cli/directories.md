---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Directorios {#directories}

Tuist organiza sus archivos en varios directorios de tu sistema, siguiendo la
[Especificación del directorio base
XDG](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
Esto proporciona una forma limpia y estándar de gestionar los archivos de
configuración, caché y estado.

## Variables de entorno compatibles {#supported-environment-variables}

Tuist admite tanto variables XDG estándar como variantes con prefijos
específicos de Tuist. Las variantes específicas de Tuist (con el prefijo
`TUIST_`) tienen prioridad, lo que le permite configurar Tuist por separado de
otras aplicaciones.

### Directorio de configuración {#configuration-directory}

**Variables de entorno:**
- `TUIST_XDG_CONFIG_HOME` (tiene prioridad)
- `XDG_CONFIG_HOME`

**Predeterminado:** `~/.config/tuist`

**Se utiliza para:**
- Credenciales del servidor (`credentials/{host}.json`)

**Ejemplo:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Directorio de caché {#cache-directory}

**Variables de entorno:**
- `TUIST_XDG_CACHE_HOME` (tiene prioridad)
- `XDG_CACHE_HOME`

**Predeterminado:** `~/.cache/tuist`

**Se utiliza para:**
- **Plugins**: caché de plugins descargados y compilados.
- **ProjectDescriptionHelpers**: Ayudas compiladas para la descripción del
  proyecto.
- **Manifiestos**: Archivos de manifiesto almacenados en caché.
- **Proyectos**: Caché del proyecto de automatización generada.
- **EditProjects**: Caché para el comando de edición.
- **Ejecuta**: Prueba y crea datos analíticos de ejecución.
- **Binarios**: Compila binarios de artefactos (no compartibles entre entornos).
- **SelectiveTests**: caché de pruebas selectivas.

**Ejemplo:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Directorio estatal {#state-directory}

**Variables de entorno:**
- `TUIST_XDG_STATE_HOME` (tiene prioridad)
- `XDG_STATE_HOME`

**Predeterminado:** `~/.local/state/tuist`

**Se utiliza para:**
- **Registros**: Archivos de registro (`logs/{uuid}.log`)
- **Bloqueos**: Archivos de bloqueo de autenticación (`{handle}.sock`)

**Ejemplo:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Orden de precedencia {#precedence-order}

A la hora de determinar qué directorio utilizar, Tuist comprueba las variables
de entorno en el siguiente orden:

1. **Variable específica de Tuist** (por ejemplo, `TUIST_XDG_CONFIG_HOME`)
2. **Variable XDG estándar** (por ejemplo, `XDG_CONFIG_HOME`)
3. **Ubicación predeterminada** (por ejemplo, `~/.config/tuist`)

Esto le permite:
- Utiliza variables XDG estándar para organizar todas tus aplicaciones de forma
  coherente.
- Sobrescribe con variables específicas de Tuist cuando necesites ubicaciones
  diferentes para Tuist.
- Confíe en los valores predeterminados sensatos sin necesidad de configuración.

## Casos de uso comunes {#common-use-cases}

### Aislar Tuist por proyecto. {#isolating-tuist-per-project}

Es posible que desee aislar la caché y el estado de Tuist por proyecto:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### Entornos CI/CD {#ci-cd-environments}

En entornos CI, es posible que desee utilizar directorios temporales:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### Depuración con directorios aislados {#debugging-with-isolated-directories}

Al depurar problemas, es posible que desee empezar de cero:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
