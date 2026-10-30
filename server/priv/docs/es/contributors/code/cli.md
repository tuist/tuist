---
{
  "title": "CLI",
  "titleTemplate": ":title · Código · Colaboradores · Tuist",
  "description": "Contribuye a la CLI de Tuist."
}
---
# CLI {#cli}

Origen: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) y [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Para qué sirve {#what-it-is-for}

La CLI es el núcleo de Tuist. Gestiona la generación de proyectos, flujos de automatización (test, run, graph e inspect) y proporciona la interfaz con el servidor de Tuist para funcionalidades como autenticación, caché, insights, previews, registry y tests selectivos.

## Cómo contribuir {#how-to-contribute}

### Requisitos {#requirements}

- macOS 14.0+
- Xcode 26+

### Configuración local {#set-up-locally}

- Clona el repositorio: `git clone git@github.com:tuist/tuist.git`
- Instala Mise usando [su script oficial de instalación](https://mise.jdx.dev/getting-started.html) (no Homebrew) y ejecuta `mise install`
- Instala las dependencias de Tuist: `tuist install`
- Genera el workspace: `tuist generate`

El proyecto generado se abre automáticamente. Si necesitas volver a abrirlo más tarde, ejecuta `open Tuist.xcworkspace`.

> [!NOTE]
> **Xed .**
>
> Si intentas abrir el proyecto con `xed .`, se abrirá el paquete, no el workspace generado por Tuist. Usa `Tuist.xcworkspace`.


### Ejecutar Tuist {#run-tuist}

#### Desde Xcode {#from-xcode}

Edita el esquema `tuist` y configura argumentos como `generate --no-open`. Establece el directorio de trabajo en la raíz del proyecto (o usa `--path`).

> [!WARNING]
> **Compilación de ProjectDescription**
>
> La CLI depende de que `ProjectDescription` esté compilado. Si falla al ejecutarse, compila primero el esquema `Tuist-Workspace`.


#### Desde la terminal {#from-the-terminal}

Primero genera el workspace:

```bash
tuist generate --no-open
```

Luego compila el ejecutable `tuist` con Xcode y ejecútalo desde DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

O mediante Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
