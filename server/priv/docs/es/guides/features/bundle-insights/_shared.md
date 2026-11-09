## Etiquetas {#tags}

Añade etiquetas al subir un bundle para distinguir variantes de compilación, entornos o canales de lanzamiento. Las etiquetas de bundle siguen la misma convención que las etiquetas de Análisis de compilaciones:

```bash
tuist inspect bundle App.ipa --tags paid production
```

En CI, también puedes definir etiquetas separadas por comas con `TUIST_BUNDLE_TAGS`:

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

Las opciones explícitas `--tags` reemplazan las etiquetas de la variable de entorno. Las etiquetas pueden contener letras, números, guiones y guiones bajos, con un máximo de 10 etiquetas por bundle y 50 caracteres por etiqueta. Las mismas opciones funcionan para bundles de Android. `--json` sigue siendo solo local y no sube ni las etiquetas ni el bundle.

Las etiquetas aparecen junto a los nombres de los bundles y en los detalles del bundle. Usa el filtro **Etiquetas** del panel y escribe una etiqueta para incluirla o excluirla de la lista de bundles. La coincidencia es exacta y distingue entre mayúsculas y minúsculas, aunque los operadores del filtro se llamen **contiene** y **no contiene**: `paid` no coincide con `paid-extra`. Para filtrar desde la CLI:

```bash
tuist bundle list --tags paid production
```

La CLI, la API (`?tags=paid,production`) y la herramienta MCP `list_bundles` (`tags: ["paid", "production"]`) devuelven los bundles que contienen **todas** las etiquetas especificadas. Las subidas mediante la API aceptan `bundle.custom_metadata.tags`; las respuestas de listado y detalle devuelven `custom_metadata.tags`. Los bundles existentes sin etiquetas siguen estando disponibles como antes. Las etiquetas filtran la lista de bundles; no modifican los gráficos de tamaño ni las líneas base de comparación automática y de umbrales.

Los clientes existentes pueden seguir subiendo y leyendo bundles sin etiquetas. Los clientes actualizados también pueden leer respuestas de servidores antiguos que omiten `custom_metadata`. El almacenamiento y el filtrado por etiquetas requieren una versión del servidor que admita etiquetas de bundle: los servidores antiguos ignoran los metadatos de subida y rechazan los filtros por etiquetas. Los clientes actualizados omiten tanto los metadatos de subida como los parámetros de consulta de etiquetas cuando no se proporcionan etiquetas.

## Entender los tamaños de los bundles {#understanding-sizes}

Para cada bundle analizado, Tuist informa de dos valores:

- **Tamaño de instalación**: el espacio que ocupa la app una vez instalada en un dispositivo.
- **Tamaño de descarga**: el tamaño comprimido que descargan los usuarios. En los bundles de Apple, este dato solo se informa para `.ipa` (el tamaño del archivo); para entradas `.xcarchive` o `.app` no está disponible.

Los tamaños se almacenan en bytes y se muestran usando la convención decimal, donde 1 MB son 1.000.000 de bytes y 1 GB son 1.000.000.000 de bytes, la misma convención que usa Apple para informar de capacidades de almacenamiento y tamaños de apps (consulta [Cómo se mide la capacidad de almacenamiento en los dispositivos Apple](https://support.apple.com/en-us/102119)). Un tamaño de instalación de 733.446.863 bytes se muestra como 733,4 MB.

## Integración continua {#continuous-integration}

Para hacer seguimiento del tamaño del bundle a lo largo del tiempo, analiza el bundle en CI. Primero, asegúrate de que tu CI esté <.localized_link href="/guides/server/authentication#continuous-integration">autenticado</.localized_link>.

Tuist también necesita saber a qué proyecto debe asociar el informe del bundle. Si aún no has conectado el proyecto, ejecuta `tuist init` o declara el identificador tú mismo:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Usa <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> para proyectos sin un manifiesto Swift, como proyectos Gradle. Cuando ambos archivos están presentes, `Tuist.swift` tiene prioridad.

Un ejemplo de flujo de trabajo de GitHub Actions:

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

Una vez configurado, puedes ver cómo evoluciona el tamaño de tu bundle con el tiempo:

![Gráfico de tamaño del bundle](/images/guides/features/bundle-size/bundle-size-graph.png)

## Comentarios en pull/merge requests {#pullmerge-request-comments}

> [!WARNING]
> **Se requiere integración con Git forge**
>
> Para recibir comentarios automáticos en pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una <.localized_link href="/guides/integrations/gitforge/github">Git forge</.localized_link>.

Cuando tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), Tuist publicará un comentario directamente en tus pull/merge requests cada vez que ejecutes `tuist inspect bundle`:

![Comentario de la app de GitHub con bundles inspeccionados](/images/guides/features/bundle-size/github-app-with-bundles.png)

## Umbrales de tamaño {#size-thresholds}

> [!WARNING]
> **Se requiere integración con Git forge**
>
> Para usar umbrales de tamaño, conecta la [app de GitHub de Tuist](https://github.com/apps/tuist) a tu proyecto. Puedes hacerlo desde la página de integraciones de tu proyecto.

Los umbrales de tamaño te permiten bloquear pull requests cuando el tamaño del bundle supera un porcentaje o un tamaño absoluto configurados en comparación con una rama base. Cuando se infringe un umbral, Tuist crea un Check Run de GitHub en el commit del PR, bloqueando la fusión hasta que se resuelva el aumento de tamaño:

![Comprobación de estado del PR que muestra que se superó el umbral de tamaño del bundle](/images/guides/features/bundle-size/github-pr-check-status.png)

El check run muestra el tamaño base, el tamaño actual y el cambio en la unidad configurada. Si el aumento es intencionado, puedes aceptarlo directamente desde la interfaz de GitHub haciendo clic en el botón **Aceptar**:

![Check run de GitHub que muestra la infracción del umbral](/images/guides/features/bundle-size/github-check-run-threshold.png)

### Configuración {#size-thresholds-configuration}

Para configurar los umbrales, ve a la pestaña **Ajustes > Bundles** de tu proyecto:

![Ajustes de umbrales de tamaño de bundle](/images/guides/features/bundle-size/bundle-size-thresholds.png)

Elige **Tamaño de instalación** o **Tamaño de descarga** y, a continuación, selecciona un **Tipo de umbral**:

- **Porcentaje (%)**: limita el crecimiento en relación con el tamaño base. Se admiten porcentajes fraccionarios como `0.47`. Los umbrales de porcentaje existentes mantienen sus valores y su comportamiento configurados.
- **Tamaño absoluto (MB)**: limita el crecimiento por una cantidad fija, independientemente del tamaño base. Introduce `1.5` para permitir hasta 1,5 MB de crecimiento. MB usa unidades decimales: 1 MB = 1.000.000 de bytes. Los valores deben resolverse en un número entero positivo de bytes.

![Configuración del umbral de crecimiento absoluto del tamaño del bundle](/images/guides/features/bundle-size/absolute-size-threshold.png)

Ambos tipos comparan con el último bundle de la **rama base** configurada que tenga el mismo nombre, el mismo tipo de bundle (por ejemplo `.app` o `.ipa`) y al menos una plataforma en común, de modo que un `.app` de simulador solo se compara con cargas de `.app` de simulador. El campo opcional **Nombre del bundle** restringe una regla a ese bundle. Una comprobación falla solo cuando el crecimiento es **mayor que** el límite; si el crecimiento es igual, los tamaños no cambian o disminuyen, la comprobación pasa. Sin una línea base coincidente o un tamaño registrado para la métrica elegida, la regla se omite. Se admite una línea base de tamaño cero para límites absolutos; los límites porcentuales siguen omitiéndola porque el crecimiento porcentual no está definido.

### Restringir quién puede aceptar {#size-thresholds-approvals}

De forma predeterminada, cualquier persona con acceso de escritura al repositorio puede aceptar un aumento de tamaño, ya que GitHub muestra el botón a esos usuarios. Para limitarlo, configura **Quién puede aceptar** en **Ajustes > Bundles**:

- **Cualquiera**: la opción predeterminada. Cualquier persona con acceso de escritura al repositorio.
- **Usuarios de GitHub seleccionados**: solo los nombres de usuario de GitHub que añadas.

Si alguien no está en la lista, la comprobación seguirá fallando con una explicación y el botón permanecerá disponible para quien pueda usarlo.
