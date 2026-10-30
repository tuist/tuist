---
{
  "title": "Análisis de compilaciones de Xcode",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Supervisa las métricas de compilación de Xcode en el panel de Tuist para monitorizar el rendimiento de las compilaciones locales y de CI."
}
---
# Análisis de compilaciones de Xcode {#xcode-build-insights}

Trabajar en proyectos grandes no debería obligarte a recompilar el mismo código una y otra vez. Tuist Build Insights te permite hacer seguimiento de las analíticas de compilación para identificar tendencias antes de que los tiempos de compilación local y en CI se conviertan en cuellos de botella.

Los análisis de compilaciones se generan con el comando `tuist inspect build`, que normalmente se añade a la acción posterior del esquema.

Para empezar a hacer seguimiento de los tiempos de compilación local, puedes aprovechar el comando `tuist inspect build` añadiéndolo a la acción posterior del esquema:

![Acción posterior para inspeccionar compilaciones](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Establece el campo "Provide build settings from" en el ejecutable o en tu objetivo de compilación principal para capturar la configuración de compilación.


> [!NOTE]
> La acción posterior al esquema no se ejecuta cuando la compilación falla.

>
> Puedes ejecutarla en ese caso estableciendo `runPostActionsOnFailure` a `YES` en el `project.pbxproj` `BuildAction` correspondiente:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Para [Mise](https://mise.jdx.dev/), activa `tuist` en el entorno de la acción posterior:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Resolución de rutas de Mise**
>
> El `PATH` de tu entorno no se hereda en la acción posterior del esquema, así que usa la ruta absoluta de Mise. Esto depende de cómo hayas instalado Mise. La configuración de compilación debería heredarse desde un objetivo para que `mise` pueda ejecutarse desde `$SRCROOT`.

Para [Homebrew](https://brew.sh/), añade las rutas de Homebrew al entorno de la acción posterior:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Las reclamaciones de actor están desactivadas por defecto. Para configurar una para la acción posterior de un esquema, establece `TUIST_ACTOR_ID` en ese script en lugar de confiar en exportaciones del shell. Xcode lanzado desde el Dock no hereda variables de `~/.zshrc`. Para suprimir explícitamente una reclamación configurada con Homebrew, usa:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Con Mise, sobrescribe el valor después de que Mise cargue su entorno:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

Usa una etiqueta explícita en lugar del valor vacío para optar por incluir la reclamación.

Una vez iniciada la sesión, las compilaciones locales se rastrean y están disponibles desde el panel de control de Tuist:

> [!TIP]
> Para acceder rápidamente al panel de control, ejecuta `tuist project show --web` desde la CLI.


![Panel de control con análisis de compilaciones](/images/guides/features/build-insights/builds-dashboard.png)

## Análisis de compilaciones en CI {#continuous-integration}

Para hacer seguimiento de los análisis de compilaciones en CI, asegúrate de que CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticado</.localized_link>.

Para CI impulsado por Xcodebuild necesitas:
- Usar <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añadir `-resultBundlePath` a tu comando de `xcodebuild`.

Sin `-resultBundlePath`, no se generan los registros de actividad ni los paquetes de resultados necesarios y `tuist inspect build` no puede analizar la compilación.

## Informes sin credenciales en una red privada {#network-trusted-publishing}

Un despliegue autoalojado puede permitir a los desarrolladores publicar informes completados sin iniciar sesión. Un operador debe configurar `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` en la instancia y reiniciarla como se describe en la <.localized_link href="/guides/server/self-host/server#network-trusted-access">guía de autoalojamiento</.localized_link>. Esto aplica a todos los proyectos compatibles; no existe una configuración en el panel de control. Configura la URL autoalojada y el proyecto en el entorno que use la acción posterior de tu esquema o terminal. La CLI descubre automáticamente la política de la instancia cuando faltan las credenciales:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

Cuando las credenciales están realmente ausentes, los registros de actividad y los paquetes XCResult se analizan localmente y se envían como informes estructurados. No se envían archivos crudos, adjuntos, cargas de cobertura/historial, procesadores remotos, referencias de fragmentos ni evidencias de ejecución selectiva. Los informes siguen siendo visibles pero no pueden actualizar el estado autenticado de los casos de prueba ni activar automatizaciones de cuarentena o fallos. El panel de control y otros comandos con privilegios siguen requiriendo inicio de sesión. Mantén la integración de caché desactivada a menos que la instancia habilite por separado el acceso a la caché de confianza de red o se provisionen credenciales.

Las credenciales presentes permanecen autenticadas. Las credenciales inválidas, corruptas, vacías o rechazadas en la actualización fallan de forma segura y permanecen en disco, de modo que los comandos posteriores no se vuelven silenciosamente no firmados. Vuelve a iniciar sesión o cierra sesión explícitamente como acción deliberada de recuperación. Actualiza cada réplica del servidor a una versión compatible con el descubrimiento antes de actualizar los clientes sin credenciales y configura la URL final del servidor sin redirecciones. Los servidores antiguos sin descubrimiento, las instancias desactivadas y los fallos de descubrimiento siguen requiriendo autenticación. No hace falta ninguna opción explícita del lado del cliente. Establece `TUIST_ACTOR_ID=""` de forma independiente para omitir la reclamación de actor configurada; la identidad verificada por credencial no se ve afectada.

## Métricas de la máquina {#machine-metrics}

Los análisis de compilaciones pueden incluir métricas de rendimiento a nivel de máquina (CPU, memoria, red y uso de disco) capturadas durante la compilación. Para habilitarlo, configura un demonio ligero en segundo plano que muestree continuamente las métricas del sistema:

```bash
tuist setup insights
```

Esto ejecuta un demonio local que muestrea métricas en segundo plano. Los datos son recogidos automáticamente por `tuist inspect build` y se suben junto con el informe de compilación.

> [!TIP]
> **CI**
>
> Ejecuta `tuist setup insights` en tus máquinas de CI antes de compilar para capturar también allí las métricas de la máquina.

Para dejar de recopilar métricas de la máquina, ejecuta:

```bash
tuist teardown insights
```

Esto descarga el LaunchAgent del demonio, elimina su plist y borra las métricas muestreadas y los registros del demonio de `~/.local/state`, de modo que no queda nada ejecutándose en segundo plano.


## Reclamación de actor del informe {#report-actor-claim}

Las solicitudes de creación de informes incluyen la cabecera opcional `x-tuist-actor-id` solo cuando estableces explícitamente `TUIST_ACTOR_ID` a una etiqueta con ámbito de organización, por ejemplo `TUIST_ACTOR_ID=employee-123 tuist inspect build`. Por defecto no se envía ninguna etiqueta y Tuist no detecta el nombre de usuario del sistema operativo. Un `TUIST_ACTOR_ID` vacío omite el identificador reportado pero no elimina la identidad verificada basada en credenciales. Los identificadores deben ser de 1–128 bytes de ASCII imprimible sin espacios; las anulaciones no válidas se omiten sin retroceder. Si un proxy personalizado rechaza cabeceras desconocidas, opta por no incluirlas con la anulación de entorno vacía.

Las credenciales individuales verificadas tienen prioridad; los identificadores reportados por el cliente se muestran como **No verificados** y nunca otorgan permisos ni se enlazan automáticamente a usuarios. Los identificadores son visibles para cualquiera que pueda ver los informes del proyecto, incluidos los espectadores públicos cuando el proyecto es público, y se incluyen en las exportaciones de datos, así que no incluyas secretos. Esto aplica a los informes de compilación, pruebas y eventos de comandos. Los servidores antiguos ignoran la cabecera opcional y los nuevos aceptan clientes antiguos sin ella. Los nuevos informes con token compartido sin identificador muestran **Desconocido**, en lugar de la organización que publica; los informes históricos conservan su atribución previa. Los listados de compilaciones y pruebas distinguen usuarios verificados de identificadores reportados no verificados. La autenticación sigue siendo necesaria a menos que la instancia autoalojada habilite explícitamente los informes sin credenciales y el cliente descubra esa política.

## Metadatos personalizados {#custom-metadata}

Puedes adjuntar metadatos a las compilaciones mediante variables de entorno para mejorar el filtrado.

### Variables de entorno

| Variable | Formato | Descripción |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Separado por comas | Múltiples etiquetas en una sola variable. |
| `TUIST_BUILD_VALUE_*` | Valor único | Par clave-valor donde el sufijo es la clave. |

### Ejemplos

Establece estos valores en CI o en tu shell antes de invocar tu compilación:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
