---
{
  "title": "Directorios",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Aprende cómo Tuist organiza sus directorios de configuración, caché y estado."
}
---
# Directorios {#directories}

Tuist organiza sus archivos en varios directorios de tu sistema, siguiendo la [Especificación de directorio base XDG](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html). Esto ofrece una forma limpia y estándar de gestionar los archivos de configuración, caché y estado.

## Variables de entorno admitidas {#supported-environment-variables}

Tuist admite tanto las variables XDG estándar como variantes con prefijo específicas de Tuist. Las variantes específicas de Tuist (con el prefijo `TUIST_`) tienen prioridad, lo que te permite configurar Tuist por separado de otras aplicaciones.

### Directorio de configuración {#configuration-directory}

**Variables de entorno:**
- `TUIST_XDG_CONFIG_HOME` (tiene prioridad)
- `XDG_CONFIG_HOME`

**Predeterminado:** `~/.config/tuist`

**Se usa para:**
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

**Se usa para:**
- **Plugins**: Caché de plugins descargados y compilados
- **ProjectDescriptionHelpers**: Ayudantes de descripción de proyecto compilados
- **Manifests**: Archivos de manifiesto en caché
- **Projects**: Caché de proyectos de automatización generados
- **EditProjects**: Caché para el comando edit
- **Runs**: Datos analíticos de ejecuciones de tests y builds
- **Binaries**: Artefactos binarios de build (no compartibles entre entornos)
- **SelectiveTests**: Caché de tests selectivos

**Ejemplo:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Directorio de estado {#state-directory}

**Variables de entorno:**
- `TUIST_XDG_STATE_HOME` (tiene prioridad)
- `XDG_STATE_HOME`

**Predeterminado:** `~/.local/state/tuist`

**Se usa para:**
- **Sessions**: Registros de sesión y grabaciones de red (`sessions/{uuid}/`)
- **Locks**: Archivos de bloqueo de autenticación (`{handle}.sock`)

**Ejemplo:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Orden de prioridad {#precedence-order}

Al determinar qué directorio usar, Tuist comprueba las variables de entorno en el siguiente orden:

1. **Variable específica de Tuist** (por ejemplo, `TUIST_XDG_CONFIG_HOME`)
2. **Variable XDG estándar** (por ejemplo, `XDG_CONFIG_HOME`)
3. **Ubicación predeterminada** (por ejemplo, `~/.config/tuist`)

Esto te permite:
- Usar variables XDG estándar para organizar todas tus aplicaciones de forma coherente
- Sobrescribir con variables específicas de Tuist cuando necesites ubicaciones diferentes para Tuist
- Confiar en valores predeterminados razonables sin ninguna configuración

## Casos de uso comunes {#common-use-cases}

### Aislar Tuist por proyecto {#isolating-tuist-per-project}

Puede que quieras aislar la caché y el estado de Tuist por proyecto:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### Entornos de CI/CD {#ci-cd-environments}

En entornos de CI, puede que quieras usar directorios temporales:

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

Al depurar problemas, puede que quieras partir de cero:

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
