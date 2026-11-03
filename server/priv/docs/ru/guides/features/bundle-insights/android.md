---
{
  "title": "Android",
  "titleTemplate": ":title · Аналитика бандлов · Возможности · Руководства · Tuist",
  "description": "Анализируйте бандлы Android-приложений (.aab) и установочные файлы (.apk) с помощью аналитики бандлов Tuist."
}
---
# Android {#bundle-insights-android}

Проанализируйте Android-бандл, указав `tuist inspect bundle` на бандл приложения или установочный файл:

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
> **Для анализа `.apk` требуется `aapt2`**, который поставляется с инструментами сборки Android SDK. Установите `ANDROID_HOME` или `ANDROID_SDK_ROOT`, чтобы Tuist мог его найти, или добавьте `aapt2` в `PATH`. Для анализа `.aab` внешние инструменты не нужны.

Команда загружает бандл в Tuist и возвращает ссылку на подробный обзор, включая сканирование содержимого и разбивку по модулям:

![Проанализированный бандл](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
