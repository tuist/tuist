---
{
  "title": "Android",
  "titleTemplate": ":title · Paket içgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Paket İçgörüler ile Android uygulama paketlerini (.aab) ve kurulabilir dosyaları (.apk) analiz edin."
}
---
# Android {#bundle-insights-android}

Bir uygulama paketini veya kurulabilir dosyayı hedef göstererek `tuist inspect bundle` ile bir Android paketini analiz edin:

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
> **Bir `.apk` analizi için `aapt2` gerekir**; bu araç Android SDK derleme araçlarıyla birlikte gelir. Tuist’in bunu bulabilmesi için `ANDROID_HOME` veya `ANDROID_SDK_ROOT` ortam değişkenlerini ayarlayın ya da `aapt2` öğesini `PATH` yoluna ekleyin. Bir `.aab` analizi için harici araçlara gerek yoktur.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
