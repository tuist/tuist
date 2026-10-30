---
{
  "title": "Proyecto Xcode generado",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Convierte un proyecto Xcode modular en Swift declarativo y desbloquea la caché de módulos, los tests selectivos, un registro de paquetes y análisis de compilación y pruebas sobre el grafo."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

Sigue esta ruta cuando quieras que Tuist describa y genere tu proyecto de Xcode a partir de manifiestos en Swift. Un proyecto generado comprime la complejidad de un proyecto modular de Xcode en una descripción concisa y declarativa del grafo. También es un requisito estricto para la caché de módulos y los tests selectivos.

Cada sección a continuación comienza explicando qué falta hoy y luego te guía por la funcionalidad que cubre esa carencia.

## Requisitos previos

- macOS con Xcode instalado.
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Crear el proyecto

La forma más rápida de verlo funcionar es con un proyecto nuevo. En un directorio vacío, ejecuta `tuist init` y elige **Crear un proyecto generado**, selecciona la plataforma, confirma el nombre, luego autentícate y elige la cuenta que debe ser propietaria del proyecto.

```bash
mkdir MyApp && cd MyApp
tuist init
```

Si lo estás haciendo desde un agente de programación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que pulses Intro) y después usa el modo no interactivo:

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

Cuando finalice init, ejecuta `tuist generate`. Tuist escribe un `.xcworkspace` junto a tus manifiestos y lo abre en Xcode. Compila y ejecuta el target. Deberías ver que la app de ejemplo se lanza en el simulador.

Ese es el estado "conectado + generando". Todo lo siguiente es opcional e independiente.

Si estás migrando una app existente, conéctala primero con la [guía de migración de proyectos de Xcode](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) y luego vuelve aquí para continuar con las secciones que se ajusten a tu caso.

## Generación del proyecto

Un `.xcodeproj` agrupa la estructura de tu app en XML: referencias de archivos, fases de compilación, dependencias de targets, esquemas y ajustes de compilación viven todos en el mismo árbol, sin ninguna primitiva para razonar sobre el grafo como grafo. A medida que el proyecto crece, esa estructura resulta más difícil de mantener en mente, y Xcode no ofrece un identificador estable para que las herramientas lo hasheen y omitan trabajo cuando nada ha cambiado.

Los proyectos generados comprimen el grafo en Swift declarativo. `Project.swift` describe directamente los targets, las dependencias y los recursos, y Tuist mantiene un modelo estable del grafo detrás de él. Ese modelo es lo que habilita las secciones siguientes: la caché de módulos lo hashea para reutilizar binarios y los tests selectivos lo hashean para omitir tests cuyas entradas no han cambiado.

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

Cada `tuist generate` produce un workspace determinista a partir de los manifiestos. Añade `.xcodeproj` y `.xcworkspace` a `.gitignore`.

## Caché de módulos

Compilar un proyecto modular de Xcode desde cero tiene un coste por máquina. Cada compañero y cada runner de CI genera su propia copia de los mismos archivos objeto. La caché de compilación de Xcode acorta el ciclo interno, pero no elimina la compilación por máquina de cada target ni puede sustituir un framework completo por un binario precompilado.

La caché de módulos sí lo hace. Compila una única vez cada dependencia cacheable de tu grafo (frameworks, bibliotecas, bundles), almacena los binarios resultantes asociándolos a un hash de las entradas del target y sustituye el target por su binario en generaciones posteriores. Los módulos sin cambios dejan de compilarse:

```bash
tuist cache
```

La primera ejecución compila todo y sube los binarios a tu cuenta. En la siguiente `tuist generate`, las dependencias sin cambios se sustituyen por sus binarios en caché y Xcode enlaza contra `.xcframework`s en lugar de compilar desde el código fuente.

## Tests selectivos

`xcodebuild test` no sabe qué tests afecta un cambio, por lo que la CI ejecuta toda la suite en cada push. A medida que la suite crece, la brecha entre lo que realmente necesita ejecutarse y lo que se ejecuta pasa de minutos a decenas de minutos.

Los tests selectivos ejecutan solo los tests afectados por lo que ha cambiado desde la última ejecución de tests exitosa, utilizando el grafo del proyecto y el mismo algoritmo de hashing en el que se basa la caché de módulos:

```bash
tuist test
```

La primera `tuist test` ejecuta todo y persiste hashes por target. Las ejecuciones posteriores omiten los targets cuyas entradas no han cambiado. Integra `tuist test` en tu CI en lugar de `xcodebuild test` y el feedback llega en segundos en vez de minutos.

## Registro de paquetes

Swift Package Manager resuelve las dependencias clonando en profundidad el historial git de cada paquete, porque los paquetes se direccionan por URL en lugar de mediante un registro. En un proyecto con decenas de paquetes transitivos, la resolución tarda minutos en un checkout limpio y se repite en cada job de CI.

El Registro de Paquetes de Tuist sirve los mismos paquetes que rastrea el Swift Package Index, pero como un registro real, de modo que SwiftPM solo obtiene el commit que realmente necesitas. Actívalo una vez configurando `registryEnabled: true` en tu `Tuist.swift`:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

Regenera. La resolución de paquetes baja de minutos a segundos.

## Análisis de compilaciones

Xcode registra las duraciones de compilación por target en el log y en el informe de compilación. Ninguno de ellos agrega datos entre ejecuciones o entre máquinas, por lo que una regresión en el tiempo de compilación suele manifestarse únicamente como una CI más lenta en general.

Análisis de compilaciones registra automáticamente la duración y los tiempos por fase de cada compilación para los esquemas generados. No hay nada adicional que configurar. Abre la pestaña **Compilaciones** del panel tras tu próximo ciclo de `tuist generate` + compilación.

## Análisis de tests

Xcode informa de los resultados por test una ejecución a la vez. No agrega la señal entre ejecuciones que realmente necesitas: tasa de inestabilidad, duración semana a semana y qué variantes de simulador fallan.

Análisis de tests registra automáticamente el resultado y la duración de cada test para los esquemas generados y correlaciona los resultados entre ejecuciones. Los tests inestables, los tests lentos y los fallos aparecen en la pestaña **Tests** del panel. Cuando se acumulan inestabilidades, ponlos en cuarentena desde el panel para que dejen de bloquear los merges.

## Involucra al equipo

La caché de módulos y los tests selectivos rinden más cuando todo el mundo trabaja sobre la misma superficie compartida. Invita a tus compañeros a la organización desde la configuración de la cuenta en el panel y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.
