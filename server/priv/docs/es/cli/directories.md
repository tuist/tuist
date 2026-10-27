---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Directorios {#directories}

Tuist organiza sus archivos a través de varios directorios en tu sistema,
siguiendo la [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
Esto proporciona una forma limpia y estándar de gestionar los archivos de
configuración, caché y estado.

## Variables de entorno compatibles {#supported-environment-variables}

Tuist admite tanto variables XDG estándar como variantes prefijadas específicas
de Tuist. Las variantes específicas de Tuist (prefijadas con `TUIST_`) tienen
preferencia, lo que te permite configurar Tuist por separado de otras
aplicaciones.

### Directorio de configuración {#configuration-directory}

**Variables de entorno:**
- `TUIST_XDG_CONFIG_HOME` (tiene prioridad)
- `XDG_CONFIG_HOME`

**Por defecto:** `~/.config/tuist`

**Se utiliza para:**
- Credenciales del servidor (`credentials/{host}.json`)

**Por ejemplo:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Directorio caché {#cache-directory}

**Variables de entorno:**
- `TUIST_XDG_CACHE_HOME` (tiene prioridad)
- `XDG_CACHE_HOME`

**Por defecto:** `~/.cache/tuist`

**Se utiliza para:**
- **Plugins**: Caché de plugins descargados y compilados
- **ProjectDescriptionHelpers**: Ayudantes de descripción de proyectos
  compilados
- **Manifiestos**: Archivos de manifiesto en caché
- **Proyectos**: Caché del proyecto de automatización generado
- **EditProjects**: Caché para el comando de edición
- **Ejecuta**: Prueba y construye datos analíticos de ejecución
- **Binarios**: Binarios de artefactos de construcción (no compartibles entre
  entornos)
- **Pruebas selectivas**: Caché de pruebas selectivas

**Por ejemplo:**
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

**Por defecto:** `~/.local/state/tuist`

**Se utiliza para:**
- **Registros**: Archivos de registro (`logs/{uuid}.log`)
- **Bloqueos**: Archivos de bloqueo de autenticación (`{handle}.sock`)

**Por ejemplo:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Orden de precedencia {#precedence-order}

Al determinar qué directorio utilizar, Tuist comprueba las variables de entorno
en el siguiente orden:

1. **Variable específica de Tuist** (por ejemplo, `TUIST_XDG_CONFIG_HOME`)
2. **Variable XDG estándar** (por ejemplo, `XDG_CONFIG_HOME`)
3. **Ubicación por defecto** (por ejemplo, `~/.config/tuist`)

Esto te permite:
- Utiliza variables XDG estándar para organizar todas tus aplicaciones de forma
  coherente
- Sustituye con variables específicas de Tuist cuando necesites diferentes
  ubicaciones para Tuist
- Confiar en valores por defecto sensibles sin ninguna configuración

## Casos de uso común {#common-use-cases}

### Aislar Tuist por proyecto {#isolating-tuist-per-project}

Tal vez quieras aislar la caché y el estado de Tuist por proyecto:

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

Al depurar problemas, es posible que desee hacer borrón y cuenta nueva:

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
