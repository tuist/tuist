---
{
  "title": "Proyecto de Xcode",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta un proyecto de Xcode existente a Tuist para aprovechar la caché de compilación de Xcode, obtener análisis de compilaciones y tests, hacer seguimiento del tamaño del bundle y usar enlaces de previsualización, sin necesidad de adoptar la generación de proyectos."
}
---
# Proyecto de Xcode {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

Sigue esta ruta cuando quieras mantener tu `.xcodeproj` o `.xcworkspace` exactamente como está e incorporar las capacidades de Tuist sin adoptar la generación de proyectos. Cada sección a continuación comienza explicando qué falta hoy y luego te guía a través de la funcionalidad que cubre esa carencia.

## Requisitos previos

- macOS con **Xcode 26 o posterior** (la caché de compilación y los análisis modernos dependen de ello).
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el proyecto

Ejecuta `tuist init` en la raíz del repositorio. Elige **Integrar `<YourApp>`** cuando Tuist detecte tu espacio de trabajo, luego autentícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto. Tuist escribe un `Tuist.swift` en la raíz que fija el identificador del proyecto para que tus compañeros de equipo y la CI compartan la misma conexión. Confírmalo.

Si estás ejecutando esto desde un agente de programación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que presiones Enter), luego usa la forma no interactiva:

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

Todo lo siguiente es opcional e independiente.

## Caché de compilación de Xcode

Xcode 26 incluye una caché de compilación por archivo, pero su almacén reside dentro del `DerivedData` de una máquina. Una compilación limpia la pobla localmente; los compañeros de equipo y los ejecutores de CI recompilan desde cero porque no ven ese almacén.

`tuist setup cache` dirige la caché de compilación de Xcode hacia la red de caché compartida de Tuist. Un acierto en cualquier máquina de desarrollo o ejecución de CI beneficia entonces a todas las demás máquinas que compilan la misma revisión.

```bash
tuist setup cache
```

Compila en Xcode. Borra los Derived Data, compila de nuevo en una segunda máquina o en un ejecutor de CI. La segunda compilación termina en una fracción del tiempo y el informe de compilación de Xcode muestra los aciertos de la caché de compilación.

## Análisis de compilaciones

Xcode registra las duraciones de compilación por objetivo en el registro y en el informe de compilación. Ninguno de ellos se agrega entre ejecuciones o entre máquinas. Una regresión en el tiempo de compilación que llega en una PR suele manifestarse solo como una CI más lenta en general, sin una señal obvia sobre qué objetivo la causó o cuándo.

El análisis de compilaciones registra la duración y los tiempos de cada fase de cada compilación para que la tendencia sea visible en el panel de control. Es una acción posterior de una sola línea en tu esquema:

1. En Xcode: **Producto → Esquema → Editar esquema…**
2. Expande **Compilación → Acciones posteriores**, haz clic en **+**, elige **Nueva acción de script de ejecución**.
3. En **Proporcionar ajustes de compilación desde**, selecciona tu objetivo de aplicación.
4. Pega la línea que coincida con cómo instalaste Tuist: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Los scripts de esquema de Xcode no heredan el `PATH` de tu shell, por lo que el shim de mise no se encuentra por sí solo. La línea de Mise anterior llama a mise por su ruta absoluta y le pide que cargue la configuración desde `$SRCROOT` para que seleccione la versión fijada en tu proyecto.
5. Compila una vez. La compilación aparece en la pestaña **Compilaciones** del panel de control en cuestión de segundos.

## Análisis de tests

El registro de tests de Xcode enumera los resultados por test una ejecución a la vez. No agrega la señal entre ejecuciones que realmente necesitas: con qué frecuencia falla un test, cuánto más lento se volvió la semana pasada, si falla solo en ciertos simuladores. Un test que pasa de fiable a inestable durante diez ejecuciones de CI parece igual que una única ejecución desafortunada.

El análisis de tests registra el resultado y la duración de cada test y correlaciona los resultados entre ejecuciones. Los tests lentos, los fallos y las inestabilidades aparecen en la pestaña **Tests** del panel de control.

1. **Producto → Esquema → Editar esquema…**
2. **Test → Acciones posteriores → +** → **Nueva acción de script de ejecución**.
3. **Proporcionar ajustes de compilación desde** tu objetivo de aplicación.
4. Pega: ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. Ejecuta la acción de test una vez. Los resultados aparecen en la pestaña **Tests** del panel de control.

## Análisis de paquetes

El tamaño de instalación y descarga de un IPA cambia con cada recurso añadido y cada símbolo enlazado. Xcode informa los tamaños bajo demanda en **Producto → Mostrar archivo**, no como una serie. Una PR que añade un recurso grande es indistinguible de cualquier otra PR en la cola de fusión.

El análisis de paquetes registra los tamaños de instalación y descarga de cada compilación analizada y puede hacer fallar una comprobación de PR cuando se supera un umbral por rama. Añade esto a tu CI justo después de tu paso de compilación:

```bash
tuist inspect bundle App.ipa
```

Abre **Análisis de paquetes** en el panel de control para ver la tendencia y configurar umbrales.

## Previews

TestFlight añade un ciclo de ida y vuelta de compilación y revisión en cada compartición. Enviar un `.ipa` firmado directamente requiere el UDID del destinatario en el perfil de aprovisionamiento. Ninguna de las dos opciones es conveniente para un diseñador o QA que solo quiere probar la rama actual.

Previews convierte una compilación en un enlace compartible que se ejecuta en un simulador o dispositivo con un solo comando:

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

Envía el enlace. Los destinatarios lo ejecutan con `tuist run <url>` o con la app de Tuist para macOS.

## Involucra al equipo

La caché y los análisis se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de la cuenta en el panel de control y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.

## Qué sigue

Si te quedas corto con este enfoque, el paso más importante son los proyectos generados por Tuist. Es un cambio real (los objetivos se describen en manifiestos de Swift en lugar de en un `.xcodeproj`), pero es lo que desbloquea la caché de módulos y los tests selectivos. Todo esto se cubre de principio a fin en la guía <.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link>.
