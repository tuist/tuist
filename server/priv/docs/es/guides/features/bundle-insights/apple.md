---
{
  "title": "Apple",
  "titleTemplate": ":title · Análisis de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Analiza paquetes de iOS, iPadOS, macOS, watchOS y tvOS (.ipa, .xcarchive, .app) con el análisis de paquetes de Tuist."
}
---
# Apple {#bundle-insights-apple}

Analiza un paquete de Apple indicando `tuist inspect bundle` a un archivo, un instalable o una aplicación compilada:

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

Cuando pasas el nombre de una aplicación en lugar de una ruta en macOS, Tuist resuelve el `.app` compilado desde los productos de compilación de Xcode (respetando `--derived-data-path` cuando está configurado), igual que hace `tuist share`.

<!-- @snippet: ./_upload-result -->

## Comparación con App Store Connect {#app-store-connect}

Tuist mide el paquete exactamente como lo proporcionas y no aplica [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). Los tamaños reportados corresponden a la variante **universal** (sin optimizar) —la fila etiquetada como "Universal" en el informe de tamaños de archivos de aplicaciones de App Store Connect—, no a las variantes por dispositivo.

Espera que los números estén en el mismo rango que la fila Universal, pero no sean idénticos:

- El **tamaño de instalación** es cercano al tamaño de instalación Universal. App Store Connect reporta un valor ligeramente mayor porque incluye sobrecarga en el dispositivo, como la asignación de bloques del sistema de archivos y la propia estimación de Apple, que una medición bruta del tamaño de archivo no captura.
- El **tamaño de descarga** es menor que el tamaño de descarga Universal. Apple cifra el binario de la aplicación después de la subida, y los datos cifrados se comprimen con menos eficiencia, por lo que la descarga comprimida de la App Store termina siendo más grande que el archivo `.ipa` que mide Tuist. Esto ocurre del lado de Apple después de la subida, por lo que no se refleja en el número de Tuist.

Las filas por dispositivo en App Store Connect son aún más pequeñas, porque app thinning elimina arquitecturas de CPU y variantes de recursos que un dispositivo específico no necesita. Tuist actualmente no reporta tamaños por dispositivo (optimizados).

<!-- @snippet: ./_shared -->
