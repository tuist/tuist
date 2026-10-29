---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Compress a modular Xcode project into declarative Swift and unlock module caching, selective testing, a package registry, and build and test insights on top of the graph."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

Sigue esta ruta cuando quieras que Tuist describa y genere tu proyecto de Xcode a partir de manifiestos Swift. Un proyecto generado comprime la complejidad de un proyecto modular de Xcode en una descripción concisa y declarativa del grafo. También es un requisito estricto para la caché de módulos y las pruebas selectivas.

Cada sección a continuación comienza con lo que falta hoy y luego te guía a través de la funcionalidad que cubre esa carencia.

## Requisitos previos

- macOS con Xcode instalado.
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Crear el proyecto

La forma más rápida de verlo funcionar es con un proyecto nuevo. En un directorio vacío, ejecuta `tuist init` y elige **Crear un proyecto generado**, selecciona la plataforma, confirma el nombre, luego autenticate y elige la cuenta que debe ser propietaria del proyecto.

```bash
mkdir MyApp && cd MyApp
tuist init
```

Si estás ejecutando esto desde un agente de codificación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que presiones Enter), luego usa el formulario no interactivo:

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

Cuando init termine, ejecuta `tuist generate`. Tuist escribe un `.xcworkspace` junto a tus manifiestos y lo abre en Xcode. Compila y ejecuta el target. Deberías ver cómo se lanza la app de ejemplo en el simulador.

Ese es el estado "conectado + generando". Todo lo siguiente es opcional e independiente.

Si estás migrando una app existente, conéctala primero con la [guía de migración de proyectos de Xcode](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project), luego regresa y continúa con las secciones que se ajusten a tu problema.

## Generación del proyecto

Un `.xcodeproj` agrupa la estructura de tu app en XML: referencias de archivos, fases de compilación, dependencias de targets, esquemas y configuraciones de compilación viven todos en el mismo árbol, sin ninguna primitiva para razonar sobre el grafo como tal. A medida que el proyecto crece, esa estructura se vuelve más difícil de mantener en mente, y Xcode no tiene un identificador estable para que las herramientas lo hasheen y omitan trabajo cuando nada ha cambiado.

Los proyectos generados comprimen el grafo en Swift declarativo. `Project.swift` describe targets, dependencias y recursos directamente, y Tuist mantiene un modelo estable del grafo detrás de él. Ese modelo es lo que habilita las secciones siguientes: la caché de módulos lo hashea para reutilizar binarios, y las pruebas selectivas lo hashean para omitir tests cuyas entradas no han cambiado.

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

Compilar un proyecto modular de Xcode desde cero tiene un coste por máquina. Cada compañero de equipo y cada runner de CI produce su propia copia de los mismos archivos objeto. La caché de compilación de Xcode acorta el ciclo interno pero no elimina la compilación por máquina de cada target, y no puede reemplazar un framework completo con un binario precompilado.

La caché de módulos sí lo hace. Compila cada dependencia cacheable en tu grafo una vez (frameworks, bibliotecas, bundles), almacena los binarios resultantes frente a un hash de las entradas del target, e intercambia el target por su binario en generaciones posteriores. Los módulos sin cambios dejan de compilarse:

```bash
tuist cache
```

La primera ejecución compila todo y sube los binarios a tu cuenta. En la siguiente `tuist generate`, las dependencias sin cambios se reemplazan con sus binarios en caché y Xcode enlaza contra `.xcframework`s en lugar de compilar desde el código fuente.

## Pruebas selectivas

`xcodebuild test` no sabe qué tests afecta un cambio, así que CI ejecuta toda la suite en cada push. A medida que la suite crece, la brecha entre lo que realmente necesita ejecutarse y lo que se ejecuta pasa de minutos a decenas de minutos.

Las pruebas selectivas ejecutan solo los tests afectados por lo que ha cambiado desde la última ejecución exitosa de tests, utilizando el grafo del proyecto y el mismo algoritmo de hashing en el que se basa la caché de módulos:

```bash
tuist test
```

La primera `tuist test` ejecuta todo y persiste hashes por target. Las ejecuciones posteriores omiten targets cuyas entradas no han cambiado. Mueve `tuist test` a CI en lugar de `xcodebuild test` y la retroalimentación llega en segundos en lugar de minutos.

## Registro de paquetes

Swift Package Manager resuelve dependencias clonando profundamente el historial git de cada paquete, porque los paquetes se direccionan por URL en lugar de por un registro. En un proyecto con docenas de paquetes transitivos, la resolución tarda minutos en un checkout limpio y se repite en cada job de CI.

El Registro de Paquetes de Tuist sirve los mismos paquetes que rastrea el Índice de Paquetes Swift, pero como un registro real, por lo que SwiftPM solo obtiene el commit que realmente necesitas. Habilítalo una vez configurando `registryEnabled: true` en tu `Tuist.swift`:

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

## Información de compilación

Xcode registra las duraciones de compilación por target en el log y en el informe de compilación. Ninguno de ellos se agrega entre ejecuciones o entre máquinas, por lo que una regresión en el tiempo de compilación suele manifestarse solo como un CI más lento en general.

La información de compilación registra automáticamente la duración y los tiempos de fase de cada compilación para esquemas generados. No hay nada extra que configurar. Abre la pestaña **Compilaciones** del dashboard después de tu próximo ciclo de `tuist generate` + compilación.

## Información de tests

Xcode informa los resultados por test una ejecución a la vez. No agrega la señal entre ejecuciones que realmente necesitas: tasa de inestabilidad, duración semana tras semana, qué variantes de simulador fallan.

La información de tests registra automáticamente el resultado y la duración de cada test para esquemas generados y correlaciona los resultados entre ejecuciones. Los tests inestables, lentos y las fallas aparecen en la pestaña **Tests** del dashboard. Cuando se acumulan inestabilidades, ponlos en cuarentena desde el dashboard para que dejen de bloquear los merges.

## Involucra al equipo

La caché de módulos y las pruebas selectivas rinden más cuando todos trabajan sobre la misma superficie compartida. Invita a tus compañeros a la organización desde la configuración de cuenta en el dashboard, y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.
