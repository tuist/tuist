---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle insights · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ Android აპლიკაციის ბანდლები (.aab) და ინსტალაციური ფაილები (.apk) Tuist Bundle Insights-ით."
}
---
# Android {#bundle-insights-android}

Android ბანდლის ანალიზისთვის მიუთითეთ `tuist inspect bundle` აპლიკაციის ბანდლზე ან ინსტალაციურ ფაილზე:

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
> **`.apk`-ის ანალიზს სჭირდება `aapt2`**, რომელიც მოყვება Android SDK build tools-თან. დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`, რათა Tuist-მა შეძლოს მისი პოვნა, ან დაამატეთ `aapt2` `PATH`-ზე. `.aab`-ის ანალიზს გარე ხელსაწყოები არ სჭირდება.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
