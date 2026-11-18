---
{
  "title": "Ejecutar previsualizaciones con la CLI",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Ejecuta aplicaciones móviles, aplicaciones de macOS y previsualizaciones de línea de comandos con la CLI de Tuist."
}
---
# Ejecuta vistas previas con la CLI

Instala la <.localized_link href="/guides/install-tuist">CLI de Tuist</.localized_link> y, a continuación, ejecuta un enlace compartido de vista previa. No necesitas el sistema de compilación que generó la vista previa:

```bash
tuist run {url}
```

Tuist selecciona una compilación compatible con tu sistema operativo, arquitectura de CPU y destino. Las vistas previas privadas requieren autenticación y acceso al proyecto.

## Aplicaciones móviles {#mobile-applications}

Selecciona un dispositivo o simulador conectado:

```bash
tuist run --device "My device" {url}
```

Los dispositivos y emuladores Android deben estar conectados mediante ADB. También puedes descargar el APK desde la página de la vista previa e instalarlo en un dispositivo Android que permita instalaciones desde esa fuente. Las compilaciones de Apple deben coincidir con la plataforma de destino y cumplir sus requisitos de firma. Para un IPA, abre el enlace de la vista previa en el dispositivo de destino para instalarlo.

## Vistas previas desde la línea de comandos {#command-line-previews}

Pasa argumentos después de `--`:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

Todo lo que vaya después de `--` se reenvía literalmente, incluidos `--verbose`, `--quiet` y `--path`. Los argumentos secundarios se excluyen de las analíticas de comandos de Tuist.

La vista previa se ejecuta con tu directorio de trabajo, entorno y entrada/salida del terminal, y devuelve el estado de salida del ejecutable. No sustituye una CLI instalada ni la añade a `PATH`. Las distribuciones de la CLI permanecen en la caché local `previews` de Tuist tras la ejecución para que los proyectos generados puedan seguir haciendo referencia a ellas; eliminar esa caché también elimina los destinos de esas referencias.

Las vistas previas de escritorio y de CLI se ejecutan como el usuario actual, no en un entorno aislado. Ejecuta únicamente compilaciones de autores y solicitudes de extracción en los que confíes.

## Selecciona una versión {#select-a-version}

`tuist run` también acepta un nombre de aplicación con `latest`, un nombre de rama o un hash de confirmación:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

Estos selectores requieren que los metadatos de Git correspondientes se hayan publicado. Para flujos de trabajo que omitan los metadatos de Git, utiliza la URL específica de la vista previa.

Para el acceso y la organización, consulta <.localized_link href="/guides/features/previews#visibility">visibilidad y seguimientos</.localized_link>.
