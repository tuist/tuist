---
{
  "title": "Apple",
  "titleTemplate": ":title · Análisis de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Analiza paquetes de iOS, iPadOS, macOS, watchOS y tvOS (.ipa, .xcarchive, .app) con el análisis de paquetes de Tuist."
}
---
# Apple {#bundle-insights-apple}

Analiza un bundle de Apple indicando `tuist inspect bundle` a un archivo, un instalable o una app compilada:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

Cuando pasas el nombre de una app en lugar de una ruta en macOS, Tuist resuelve la `.app` compilada desde los productos de compilación de Xcode (respetando `--derived-data-path` cuando está configurado), igual que hace `tuist share`.

El comando sube el bundle a Tuist y devuelve un enlace a una vista detallada, que incluye un escaneo del contenido y un desglose por módulos:

![Bundle analizado](/images/guides/features/bundle-size/analyzed-bundle.png)

## Comparación con App Store Connect {#app-store-connect}

Tuist mide el bundle exactamente como lo proporcionas y no aplica [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). Los tamaños reportados corresponden a la variante **universal** (sin afinar) —la fila etiquetada como "Universal" en el informe de tamaños de archivos de app de App Store Connect—, no a las variantes por dispositivo.

Espera que los números estén en el mismo rango que la fila Universal, pero no sean idénticos:

- El **Tamaño de instalación** es cercano al tamaño de instalación Universal. App Store Connect reporta un valor ligeramente mayor porque incluye sobrecarga en el dispositivo, como la asignación de bloques del sistema de archivos y la propia estimación de Apple, que una medición directa del tamaño de archivo no captura.
- El **Tamaño de descarga** es menor que el tamaño de descarga Universal. Apple cifra el binario de la app después de la subida, y los datos cifrados se comprimen con menos eficiencia, por lo que la descarga comprimida de la App Store resulta más grande que el archivo `.ipa` que mide Tuist. Esto ocurre del lado de Apple después de la subida, por lo que no se refleja en el número de Tuist.

Las filas por dispositivo en App Store Connect son aún más pequeñas, porque el app thinning elimina arquitecturas de CPU y variantes de recursos que un dispositivo específico no necesita. Tuist no reporta actualmente tamaños por dispositivo (afinados).

<!-- @snippet: ./_shared -->
