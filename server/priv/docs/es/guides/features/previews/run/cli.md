---
{
  "title": "Ejecutar previsualizaciones con la CLI",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Ejecuta aplicaciones móviles, aplicaciones de macOS y previsualizaciones de línea de comandos con la CLI de Tuist."
}
---
# Ejecuta previsualizaciones con la CLI

Instala la <.localized_link href="/guides/install-tuist">CLI de Tuist</.localized_link> y, a continuación, ejecuta un enlace compartido de previsualización. No necesitas el sistema de compilación que generó la previsualización:

```bash
tuist run {url}
```

Tuist selecciona una compilación compatible con tu sistema operativo, arquitectura de CPU y destino. Las previsualizaciones privadas requieren autenticación y acceso al proyecto.

## Aplicaciones móviles {#mobile-applications}

Selecciona un dispositivo o simulador conectado:

```bash
tuist run --device "My device" {url}
```

Los dispositivos y emuladores Android deben estar conectados mediante ADB. También puedes descargar el APK desde la página de previsualización e instalarlo en un dispositivo Android que permita la instalación desde esa fuente. Las compilaciones para Apple deben coincidir con la plataforma de destino y cumplir sus requisitos de firma. Para un IPA, abre el enlace de previsualización en el dispositivo de destino para instalarlo.

## Previsualizaciones desde la línea de comandos {#command-line-previews}

Pasa argumentos después de `--`:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

Todo lo que vaya después de `--` se reenvía tal cual, incluidos `--verbose`, `--quiet` y `--path`. Los argumentos hijos quedan excluidos de las analíticas de comandos de Tuist.

La previsualización se ejecuta con tu directorio de trabajo, entorno y entrada/salida de terminal, y devuelve el código de salida del ejecutable. No sustituye una CLI instalada ni la añade a `PATH`. Las distribuciones de la CLI permanecen en la caché local `previews` de Tuist tras la ejecución para que los proyectos generados puedan seguir haciendo referencia a ellas; eliminar esa caché también elimina los destinos de esas referencias.

Las previsualizaciones de escritorio y de CLI se ejecutan como el usuario actual, no en un entorno aislado. Ejecuta solo compilaciones de autores y solicitudes de extracción en los que confíes.

## Selecciona una versión {#select-a-version}

`tuist run` también acepta un nombre de aplicación con `latest`, un nombre de rama o un hash de commit:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

Estos selectores requieren que los metadatos de Git correspondientes se hayan publicado. Para flujos de trabajo que omiten los metadatos de Git, utiliza la URL específica de la previsualización.

Para obtener información sobre acceso y organización, consulta <.localized_link href="/guides/features/previews#visibility">visibilidad y pistas</.localized_link>.
