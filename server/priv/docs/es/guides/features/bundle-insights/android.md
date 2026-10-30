---
{
  "title": "Android",
  "titleTemplate": ":title · Análisis de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Analiza los paquetes de aplicaciones Android (.aab) y los instalables (.apk) con el análisis de paquetes de Tuist."
}
---
# Android {#bundle-insights-android}

Analiza un bundle de Android indicando `tuist inspect bundle` hacia un app bundle o un instalable:

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

El comando sube el bundle a Tuist y devuelve un enlace a una visión general detallada, que incluye un análisis del contenido y un desglose por módulos:

![Bundle analizado](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
