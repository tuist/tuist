---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Fuente:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
y
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Para qué sirve {#what-it-is-for}

La CLI es el corazón de Tuist. Se encarga de la generación de proyectos, los
flujos de trabajo de automatización (prueba, ejecución, gráfico e inspección) y
proporciona la interfaz con el servidor Tuist para funciones como autenticación,
caché, información, vistas previas, registro y pruebas selectivas.

## Cómo contribuir {#how-to-contribute}

### Requisitos {#requirements}

- macOS 14.0+
- Xcode 26+

### Configurar localmente {#set-up-locally}

- Clona el repositorio: `git clone git@github.com:tuist/tuist.git`
- Instala Mise utilizando [su script de instalación
  oficial](https://mise.jdx.dev/getting-started.html) (no Homebrew) y ejecuta
  `mise install`
- Instala las dependencias de Tuist: `tuist install`
- Genera el espacio de trabajo: `tuist generate`

El proyecto generado se abre automáticamente. Si necesitas volver a abrirlo más
tarde, ejecuta `open Tuist.xcworkspace`.

::: info XED .
<!-- -->
Si intentas abrir el proyecto utilizando `xed .`, se abrirá el paquete, no el
espacio de trabajo generado por Tuist. Utiliza `Tuist.xcworkspace`.
<!-- -->
:::

### Ejecuta Tuist. {#run-tuist}

#### Desde Xcode {#from-xcode}

Edita el archivo `tuist` y configura argumentos como `generate --no-open`.
Establece el directorio de trabajo en la raíz del proyecto (o utiliza `--path`).

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
La CLI depende de que se compile `ProjectDescription`. Si no se ejecuta, compile
primero el esquema `Tuist-Workspace`.
<!-- -->
:::

#### Desde el terminal {#from-the-terminal}

Primero genera el espacio de trabajo:

```bash
tuist generate --no-open
```

A continuación, compile el ejecutable `tuist` con Xcode y ejecútelo desde
DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

O a través del Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
