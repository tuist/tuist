---
{
  "title": "Android",
  "titleTemplate": ":title · 번들 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist Bundle Insights로 Android 앱 번들(.aab)과 설치 파일(.apk)을 분석하세요."
}
---
# Android {#bundle-insights-android}

앱 번들 또는 설치 가능 파일을 `tuist inspect bundle`에 지정하여 Android 번들을 분석하세요:

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
> **`.apk`를 분석하려면 Android SDK 빌드 도구에 포함된 `aapt2`가 필요합니다.** Tuist가 이를 찾을 수 있도록 `ANDROID_HOME` 또는 `ANDROID_SDK_ROOT`를 설정하거나, `aapt2`를 `PATH`에 추가하세요. `.aab` 분석에는 외부 도구가 필요하지 않습니다.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
