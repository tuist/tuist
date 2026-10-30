---
{
  "title": "Profiles",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Runner profiles are named machine shapes you reference from runs-on to choose a platform, size, and Xcode version for Tuist Runners."
}
---
# Perfiles {#profiles}

Un **perfil** es una forma de máquina con nombre, del ámbito de la cuenta. Lo referencias desde el `runs-on` de un flujo de trabajo, y Tuist enruta el trabajo a un runner que coincida. Los perfiles mantienen las opciones de infraestructura (plataforma, tamaño, versión de Xcode) en un solo lugar en lugar de estar dispersas en cada archivo de flujo de trabajo, y te ofrecen una etiqueta estable para apuntar la CI.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

La etiqueta es el nombre del perfil con el prefijo `tuist-`. Un perfil llamado `macos` es `runs-on: tuist-macos`; un perfil llamado `linux-large` es `runs-on: tuist-linux-large`. La coincidencia no distingue entre mayúsculas y minúsculas.

## Perfiles predeterminados {#default-profiles}

Cada cuenta habilitada para Runners comienza con dos perfiles para que puedas usar la flota sin configurar nada:

{{runner_default_profiles_table}}

Ambos apuntan a la <.localized_link href="/guides/features/runners/profiles#machine-shapes">forma</.localized_link> predeterminada para su plataforma. Están **protegidos**, por lo que no se pueden eliminar y las etiquetas de las que dependen tus flujos de trabajo siempre se resuelven. Aún puedes cambiar su forma o versión de Xcode, y puedes crear perfiles adicionales para otros tamaños o versiones de Xcode.

## Formas de máquina {#machine-shapes}

Los runners están disponibles en macOS (silicio de Apple, virtualizados en la flota de Mac) y Linux. Cada perfil fija una forma de máquina, un par `(vCPUs, memory)`, del catálogo siguiente.

### Linux {#linux}

{{runner_linux_shapes_table}}

Cada perfil de Linux admite <.localized_link href="/guides/features/runners#android-emulators">emuladores de Android con aceleración por hardware</.localized_link> a través de `/dev/kvm`. No se requiere un perfil KVM separado.

### macOS {#macos}

{{runner_macos_shapes_table}}

Las formas de macOS más grandes se ejecutan en menos máquinas de la flota, por lo que un trabajo que solicite una puede esperar más tiempo para iniciarse que el mismo trabajo en una forma más pequeña. Opta por una forma más grande cuando un trabajo esté limitado por la CPU, y mantén la forma predeterminada para todo lo demás. Si no estás seguro, ejecuta el trabajo en ambas y compara las duraciones en el panel.

Los perfiles de macOS también fijan una **versión de Xcode**. La versión selecciona una imagen de runner con ese Xcode preinstalado, por lo que los trabajos comienzan con la cadena de herramientas ya lista. Versiones admitidas actualmente:

{{runner_macos_xcode_versions}}

> [!NOTE]
> El catálogo evoluciona a medida que añadimos hardware y lanzamientos de Xcode. El formulario **Nuevo perfil** del panel y `tuist runner profile catalog` siempre muestran las formas y versiones de Xcode disponibles actualmente para tu cuenta, así que considéralos como la fuente de verdad.

El nombre de un runner de macOS muestra la versión de macOS que ejecuta, la versión de Xcode del perfil y su forma, por ejemplo `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`. El nombre aparece en el paso **Configurar trabajo** del trabajo en GitHub y en los detalles del trabajo en el panel de Tuist.

## Crear un perfil {#creating-a-profile}

1. Abre la sección **Runners → Perfiles** del panel de tu cuenta.
2. Elige **Nuevo perfil**.
3. Dale un nombre, elige una plataforma y selecciona una forma. Para macOS, elige también una versión de Xcode.
4. Guarda y luego haz referencia a él desde un flujo de trabajo con `runs-on: tuist-<name>`.

También puedes gestionar perfiles desde la línea de comandos. Crear, modificar y eliminar perfiles requiere administración de la cuenta, como en el panel, o un token de cuenta con el ámbito `account:runners:write`:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Los agentes pueden hacer lo mismo a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link>.

Por ejemplo, un perfil llamado `linux-large` en la forma de 8 vCPU / 32 GB:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

O un perfil de macOS llamado `xcode-26-4` fijado a Xcode `26.4.1`, para que un trabajo pueda ejecutarse en una cadena de herramientas anterior mientras tu perfil `macos` predeterminado sigue la última:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
