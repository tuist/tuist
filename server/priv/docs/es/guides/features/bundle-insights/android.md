---
{
  "title": "Android",
  "titleTemplate": ":title · Análisis de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Analiza los paquetes de aplicaciones Android (.aab) y los instalables (.apk) con el análisis de paquetes de Tuist."
}
---
# Android {#bundle-insights-android}

Analiza un paquete de Android apuntando `tuist inspect bundle` a un paquete de aplicación o a un instalable:

::: code-group
```bash [Analyze an .aab (recommended)]
tuist inspect bundle App.aab
```
```bash [Analyze an .apk]
tuist inspect bundle App.apk
```
<!-- -->
:::

> [!NOTE]
> **Analizar un `.apk` requiere `aapt2`**, que se incluye con las herramientas de compilación del SDK de Android. Configura `ANDROID_HOME` o `ANDROID_SDK_ROOT` para que Tuist pueda encontrarlo, o añade `aapt2` al `PATH`. Analizar un `.aab` no necesita herramientas externas.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
