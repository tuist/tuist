## Comprensión del tamaño de los bundles {#understanding-sizes}

Para cada bundle analizado, Tuist informa dos valores:

- **Tamaño de instalación**: el espacio que ocupa la app una vez instalada en un dispositivo.
- **Tamaño de descarga**: el tamaño comprimido que descargan los usuarios. Para los bundles de Apple, esto solo se informa para `.ipa` (el tamaño del archivo); para entradas de `.xcarchive` o `.app` no está disponible.

Los tamaños se almacenan en bytes y se muestran usando la convención decimal, donde 1 MB son 1.000.000 de bytes y 1 GB son 1.000.000.000 de bytes, la misma convención que usa Apple para informar sobre el almacenamiento y los tamaños de las apps (consulta [Cómo se mide la capacidad de almacenamiento en los dispositivos Apple](https://support.apple.com/en-us/102119)). Un tamaño de instalación de 733.446.863 bytes se muestra como 733,4 MB.

## Integración continua {#continuous-integration}

Para hacer seguimiento del tamaño del bundle a lo largo del tiempo, analiza el bundle en CI. Primero, asegúrate de que tu CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticado</.localized_link>.

Tuist también necesita saber a qué proyecto informar el bundle. Si aún no has conectado el proyecto, ejecuta `tuist init` o declara el identificador tú mismo:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Usa <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> para proyectos sin un manifiesto Swift, como los proyectos Gradle. Cuando ambos archivos están presentes, `Tuist.swift` tiene prioridad.

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

![Gráfico de tamaño de bundle](/images/guides/features/bundle-size/bundle-size-graph.png)

## Comentarios en pull/merge requests {#pullmerge-request-comments}

> [!WARNING]
> **Se requiere integración con plataforma Git**
>
> Para obtener comentarios automáticos en pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.

Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), Tuist publicará un comentario directamente en tus pull/merge requests cada vez que ejecutes `tuist inspect bundle`:

![Comentario de la app de GitHub con bundles inspeccionados](/images/guides/features/bundle-size/github-app-with-bundles.png)

## Umbrales de tamaño {#size-thresholds}

> [!WARNING]
> **Se requiere integración con Git Forge**
>
> Para usar umbrales de tamaño, conecta la [app de Tuist para GitHub](https://github.com/apps/tuist) a tu proyecto. Puedes hacerlo desde la página de integraciones de tu proyecto.

Los umbrales de tamaño te permiten bloquear pull requests cuando el tamaño del bundle aumenta más allá de un porcentaje o tamaño absoluto configurado en comparación con una rama base. Cuando se viola un umbral, Tuist crea una ejecución de comprobación de GitHub en el commit de la PR, bloqueando la fusión hasta que se resuelva el aumento de tamaño:

![Comprobación de estado de PR que muestra que se superó el umbral de tamaño del bundle](/images/guides/features/bundle-size/github-pr-check-status.png)

La ejecución de comprobación muestra el tamaño base, el tamaño actual y el cambio en la unidad configurada. Si el aumento es intencional, puedes aceptarlo directamente desde la interfaz de GitHub haciendo clic en el botón **Aceptar**:

![Ejecución de comprobación de GitHub que muestra la violación del umbral](/images/guides/features/bundle-size/github-check-run-threshold.png)

### Configuración {#size-thresholds-configuration}

Para configurar los umbrales, ve a la pestaña **Configuración > Bundles** de tu proyecto:

![Configuración de umbrales de tamaño de bundle](/images/guides/features/bundle-size/bundle-size-thresholds.png)

Elige **Tamaño de instalación** o **Tamaño de descarga**, luego selecciona un **Tipo de umbral**:

- **Porcentaje (%)**: limita el crecimiento en relación con el tamaño base. Se admiten porcentajes fraccionarios como `0.47`. Los umbrales de porcentaje existentes conservan sus valores y comportamiento configurados.
- **Tamaño absoluto (MB)**: limita el crecimiento por una cantidad fija, independientemente del tamaño base. Introduce `1.5` para permitir hasta 1,5 MB de crecimiento. MB usa unidades decimales: 1 MB = 1.000.000 de bytes. Los valores deben resolverse en un número entero positivo de bytes.

![Configuración del umbral de crecimiento absoluto del tamaño del bundle](/images/guides/features/bundle-size/absolute-size-threshold.png)

Ambos tipos comparan con el último bundle en la **rama base** configurada con el mismo nombre, el mismo tipo de bundle (por ejemplo, `.app` o `.ipa`), y al menos una plataforma en común, por lo que un `.app` de simulador solo se compara con cargas de `.app` de simulador. El **Nombre del bundle** opcional restringe una regla a ese bundle. Una comprobación falla solo cuando el crecimiento es **mayor que** el límite; el crecimiento igual, los tamaños sin cambios y las disminuciones pasan. Sin una base coincidente o un tamaño registrado para la métrica elegida, la regla se omite. Se admite una base de tamaño cero para límites absolutos; los límites de porcentaje siguen omitiéndola porque el crecimiento porcentual no está definido.

### Restricción de quién puede aceptar {#size-thresholds-approvals}

De forma predeterminada, cualquier persona con acceso de escritura al repositorio puede aceptar un aumento de tamaño, porque es a quien GitHub muestra el botón. Para restringirlo, configura **Quién puede aceptar** en **Configuración > Bundles**:

- **Cualquiera**: la opción predeterminada. Cualquier persona con acceso de escritura al repositorio.
- **Usuarios de GitHub seleccionados**: solo los nombres de usuario de GitHub que añadas.

Alguien que no esté en la lista deja la comprobación fallando con una explicación, y el botón permanece para quien pueda usarlo.
