---
{
  "title": "Perfiles",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Los perfiles de runner son configuraciones de máquina con nombre a las que haces referencia desde runs-on para elegir la plataforma, el tamaño y la versión de Xcode para los Tuist Runners."
}
---
# Perfiles {#profiles}

Un **perfil** es una forma de máquina con nombre, definida a nivel de cuenta. Lo referencias desde el campo `runs-on` de un flujo de trabajo y Tuist enruta el trabajo a un runner que coincida. Los perfiles centralizan las elecciones de infraestructura (plataforma, tamaño, versión de Xcode) en un solo lugar, en vez de dispersas por cada archivo de flujo de trabajo, y te ofrecen una etiqueta estable para apuntar la CI.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

La etiqueta es el nombre del perfil con el prefijo `tuist-`. Un perfil llamado `macos` se usa como `runs-on: tuist-macos`; un perfil llamado `linux-large` se usa como `runs-on: tuist-linux-large`. La coincidencia no distingue entre mayúsculas y minúsculas.

## Perfiles predeterminados {#default-profiles}

Cada cuenta habilitada para Runners comienza con dos perfiles para que puedas usar la flota sin configurar nada:

{{runner_default_profiles_table}}

Ambos apuntan a la <.localized_link href="/guides/features/runners/profiles#machine-shapes">forma</.localized_link> predeterminada de su plataforma. Están **protegidos**, por lo que no pueden eliminarse y las etiquetas de las que dependen tus flujos de trabajo siempre se resuelven. Aun así puedes cambiar su forma o versión de Xcode, y crear perfiles adicionales para otros tamaños o versiones de Xcode.

## Formas de máquina {#machine-shapes}

Los runners están disponibles en macOS (Apple Silicon, virtualizados en la flota de Mac) y Linux. Cada perfil fija una forma de máquina, un par `(vCPUs, memory)`, del catálogo siguiente.

### Linux {#linux}

{{runner_linux_shapes_table}}

Cada perfil de Linux admite <.localized_link href="/guides/features/runners#android-emulators">emuladores de Android con aceleración por hardware</.localized_link> a través de `/dev/kvm`. No hace falta un perfil KVM separado.

### macOS {#macos}

{{runner_macos_shapes_table}}

Las formas de macOS más grandes se ejecutan en menos máquinas de la flota, por lo que un trabajo que solicita una de ellas puede tardar más en iniciarse que el mismo trabajo en una forma más pequeña. Opta por una forma más grande cuando un trabajo esté limitado por la CPU y mantén la forma predeterminada para todo lo demás. Si no estás seguro, ejecuta el trabajo en ambas y compara las duraciones en el panel.

Los perfiles de macOS también fijan una **versión de Xcode**. La versión selecciona una imagen de runner con esa versión de Xcode preinstalada, de modo que los trabajos arrancan con la toolchain ya lista. Versiones compatibles actualmente:

{{runner_macos_xcode_versions}}

> [!NOTE]
> El catálogo evoluciona a medida que añadimos hardware y lanzamientos de Xcode. El formulario **Nuevo perfil** del panel y `tuist runner profile catalog` siempre muestran las formas y versiones de Xcode disponibles para tu cuenta, así que considéralos la fuente de verdad.

El nombre de un runner de macOS muestra la versión de macOS que ejecuta, la versión de Xcode del perfil y su forma, por ejemplo `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`. El nombre aparece en el paso **Set up job** del trabajo en GitHub y en los detalles del trabajo en el panel de Tuist.

## Crear un perfil {#creating-a-profile}

1. Abre la sección **Runners → Profiles** del panel de tu cuenta.
2. Elige **Nuevo perfil**.
3. Asígnale un nombre, selecciona una plataforma y elige una forma. Para macOS, elige también una versión de Xcode.
4. Guarda y luego referencia el perfil desde un flujo de trabajo con `runs-on: tuist-<name>`.

También puedes gestionar perfiles desde la línea de comandos. Crear, modificar y eliminar perfiles requiere permisos de administración de la cuenta, como en el panel, o un token de cuenta con el ámbito `account:runners:write`:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Los agentes pueden hacer lo mismo a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link>.

Por ejemplo, un perfil llamado `linux-large` con la forma de 8 vCPU / 32 GB:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

O un perfil de macOS llamado `xcode-26-4` fijado a Xcode `26.4.1`, para que un trabajo pueda ejecutarse con una toolchain anterior mientras tu perfil predeterminado `macos` sigue la última versión:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
